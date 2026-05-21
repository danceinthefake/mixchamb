defmodule Mixchamb.SystemHealthTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.SystemHealth

  describe "snapshot/0" do
    test "returns the expected top-level keys" do
      snap = SystemHealth.snapshot()

      assert is_map(snap)
      assert is_map(snap.beam)
      assert is_map(snap.memory)
      assert is_list(snap.ets)
      assert is_map(snap.db)
      assert is_map(snap.chambers)
      assert is_integer(snap.at)
    end

    test "beam snapshot carries positive process / scheduler counts" do
      %{beam: beam} = SystemHealth.snapshot()

      assert beam.process_count > 0
      assert beam.process_limit >= beam.process_count
      assert beam.schedulers_online > 0
      assert beam.schedulers_total >= beam.schedulers_online
      assert is_integer(beam.run_queue)
      assert is_binary(beam.otp_release)
    end

    test "memory snapshot has the expected segments" do
      %{memory: mem} = SystemHealth.snapshot()

      for key <- [:total, :processes, :atom, :binary, :code, :ets, :system] do
        assert is_integer(Map.fetch!(mem, key))
      end

      assert mem.total > 0
    end

    test "ets snapshot includes both mixchamb-owned tables" do
      ets = SystemHealth.snapshot().ets

      assert Enum.find(ets, &(&1.table == :chamber_restart_counts))
      assert Enum.find(ets, &(&1.table == Mixchamb.RateLimiter.table()))

      for row <- ets do
        assert is_integer(row.size)
        assert is_integer(row.memory_bytes)
      end
    end

    test "db snapshot reports an OK status when Postgres is up" do
      %{db: db} = SystemHealth.snapshot()
      assert db.status == :ok
      assert is_integer(db.active_connections)
      assert db.pool_size > 0
    end
  end
end
