defmodule MixwaveWeb.LandingLiveTest do
  use MixwaveWeb.ConnCase, async: false

  alias Mixwave.Chambers

  describe "GET /" do
    test "renders both entry cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Chaos chamber"
      assert html =~ "Secret chamber"
    end
  end

  describe "enter_chaos" do
    test "ensures the chaos chamber exists and navigates to it", %{conn: conn} do
      assert is_nil(Chambers.find_by_slug(Chambers.chaos_slug()))

      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: target}}} =
               view |> element("button[phx-click=\"enter_chaos\"]") |> render_click()

      assert target == ~p"/chamber/#{Chambers.chaos_slug()}"
      assert %{} = Chambers.find_by_slug(Chambers.chaos_slug())
    end
  end

  describe "create_chamber" do
    test "creates a new chamber and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: target}}} =
               view |> element("button[phx-click=\"create_chamber\"]") |> render_click()

      assert target =~ ~r"^/chamber/[A-Za-z0-9_-]+$"
      slug = String.replace_prefix(target, "/chamber/", "")
      assert Chambers.find_by_slug(slug)
    end
  end
end
