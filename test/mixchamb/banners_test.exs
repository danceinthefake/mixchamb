defmodule Mixchamb.BannersTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.Banners

  describe "set_banner/3" do
    test "persists and returns the new active banner" do
      assert {:ok, banner} = Banners.set_banner("Heads up — deploy", 5, "admin")

      assert banner.message == "Heads up — deploy"
      assert banner.inserted_by == "admin"
      assert DateTime.compare(banner.expires_at, DateTime.utc_now()) == :gt
    end

    test "broadcasts {:banner_changed, banner} on success" do
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, Banners.topic())

      {:ok, banner} = Banners.set_banner("Yo", 5, "admin")

      assert_receive {:banner_changed, ^banner}, 500
    end

    test "rejects an empty message" do
      assert {:error, changeset} = Banners.set_banner("", 5, "admin")
      assert "can't be blank" in errors_on(changeset).message
    end
  end

  describe "current_banner/0" do
    test "returns the newest non-expired banner" do
      {:ok, _old} = Banners.set_banner("Old one", 5, "admin")
      {:ok, _newer} = Banners.set_banner("Newest", 5, "admin")

      assert %{message: "Newest"} = Banners.current_banner()
    end

    test "ignores expired rows" do
      # Insert one with a past expiry by clearing immediately.
      {:ok, _} = Banners.set_banner("ephemeral", 1, "admin")
      {:ok, _} = Banners.clear_banner()

      assert Banners.current_banner() == nil
    end

    test "returns nil when no rows exist" do
      assert Banners.current_banner() == nil
    end
  end

  describe "clear_banner/0" do
    test "expires the active banner and broadcasts nil" do
      {:ok, _} = Banners.set_banner("Hello", 5, "admin")
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, Banners.topic())

      {:ok, _} = Banners.clear_banner()

      assert_receive {:banner_changed, nil}, 500
      assert Banners.current_banner() == nil
    end

    test "is a no-op when nothing is active" do
      assert {:ok, nil} = Banners.clear_banner()
    end
  end
end
