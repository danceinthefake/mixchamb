defmodule MixwaveWeb.ChamberLiveTest do
  use MixwaveWeb.ConnCase, async: false

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Chambers.Server

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_anonymous_user()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})

    {:ok, chamber} = Chambers.create_chamber(user.id)

    on_exit(fn ->
      case Registry.lookup(Mixwave.Chambers.Registry, chamber.slug) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Mixwave.Chambers.Supervisor, pid)
        _ -> :ok
      end
    end)

    %{conn: conn, user: user, chamber: chamber}
  end

  describe "mount" do
    test "renders the chamber and its title", %{conn: conn, chamber: chamber} do
      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      assert html =~ chamber.slug or html =~ "Chamber"
    end

    test "starts the per-chamber GenServer", %{conn: conn, chamber: chamber} do
      {:ok, _view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      assert [{pid, _}] = Registry.lookup(Mixwave.Chambers.Registry, chamber.slug)
      assert Process.alive?(pid)
    end

    test "redirects to / when the slug doesn't exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/chamber/does-not-exist")
    end
  end

  describe "creator-only invite banner" do
    test "shows for the creator while the chamber is in grace", %{conn: conn, chamber: chamber} do
      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      assert html =~ "Share this chamber"
    end

    test "hides for non-creators", %{conn: conn, chamber: chamber} do
      {:ok, other} = Accounts.create_anonymous_user()
      conn = Plug.Test.init_test_session(conn, %{"user_id" => other.id})

      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      refute html =~ "Share this chamber"
    end
  end

  describe "note event roundtrip" do
    test "pushing a note records it in the GenServer + broadcasts on the chamber topic",
         %{conn: conn, chamber: chamber} do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.topic(chamber.slug))

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}
      render_hook(view, "note", payload)

      assert_receive {:chamber_note, %{kind: :note, payload: received}}, 500
      assert received["instrument"] == "drums"
      assert received["display_name"]

      info = Server.info(chamber.slug)
      assert info.event_count >= 1
    end
  end
end
