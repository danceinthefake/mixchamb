defmodule Mixchamb.AuditTest do
  use Mixchamb.DataCase, async: true

  alias Mixchamb.Audit

  describe "log_action/4" do
    test "persists the row with the supplied admin_user + metadata" do
      assert {:ok, action} =
               Audit.log_action("kill_chamber", "chamber:foo", "admin", %{pid: "#PID<0.1.0>"})

      assert action.action == "kill_chamber"
      assert action.target == "chamber:foo"
      assert action.admin_user == "admin"
      assert action.metadata == %{pid: "#PID<0.1.0>"}
    end

    test "requires action + admin_user" do
      # No action.
      changeset_or_error = Audit.log_action("", "x", "admin")
      assert match?({:error, _}, changeset_or_error)
    end
  end

  describe "log/3" do
    test "auto-fills admin_user from current :admin_user app env" do
      # Read the configured value rather than mutate it — flipping
      # the env mid-test races with admin_session tests that read
      # the same key.
      configured = Application.get_env(:mixchamb, :admin_user, "admin")
      assert {:ok, action} = Audit.log("delete_chamber", "chamber:bar")
      assert action.admin_user == configured
    end
  end

  describe "recent_actions/1 + count_actions/0" do
    test "returns rows newest first, capped by limit" do
      {:ok, _} = Audit.log_action("a", nil, "admin")
      :timer.sleep(2)
      {:ok, _} = Audit.log_action("b", nil, "admin")
      :timer.sleep(2)
      {:ok, _} = Audit.log_action("c", nil, "admin")

      rows = Audit.recent_actions(2)
      assert length(rows) == 2
      assert [first, second | _] = rows
      assert first.action == "c"
      assert second.action == "b"

      assert Audit.count_actions() == 3
    end
  end
end
