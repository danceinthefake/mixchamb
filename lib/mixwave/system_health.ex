defmodule Mixwave.SystemHealth do
  @moduledoc """
  One-shot snapshots of BEAM + Postgres + ETS state for the admin
  Health tab.

  Everything here is a cheap read — `:erlang` BIFs, ETS info, one
  `pg_stat_activity` query. The LV ticks `snapshot/0` every couple
  of seconds; there's no GenServer or polling in this module.
  """

  alias Mixwave.Repo

  # ETS tables we own + a friendly label for the admin UI. Excludes
  # tables created by deps (Presence, PubSub) since those are
  # already covered by LiveDashboard at /dev/dashboard and would
  # noise up this view.
  @owned_ets [
    {:chamber_restart_counts, "Chamber restart counts"},
    {Mixwave.RateLimiter.table(), "Rate limiter buckets"}
  ]

  @doc """
  Returns the snapshot the Health LV reads.
  """
  def snapshot do
    %{
      beam: beam_snapshot(),
      memory: memory_snapshot(),
      ets: ets_snapshot(),
      db: db_snapshot(),
      chambers: chamber_snapshot(),
      at: System.system_time(:second)
    }
  end

  ## BEAM

  defp beam_snapshot do
    {{:input, input_bytes}, {:output, output_bytes}} = :erlang.statistics(:io)
    {total_reductions, _since_last} = :erlang.statistics(:reductions)

    %{
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      schedulers_online: :erlang.system_info(:schedulers_online),
      schedulers_total: :erlang.system_info(:schedulers),
      run_queue: :erlang.statistics(:run_queue),
      reductions_total: total_reductions,
      io_in_bytes: input_bytes,
      io_out_bytes: output_bytes,
      otp_release: List.to_string(:erlang.system_info(:otp_release)),
      system_version: :erlang.system_info(:system_version) |> List.to_string() |> String.trim()
    }
  end

  ## Memory

  defp memory_snapshot do
    mem = :erlang.memory()

    %{
      total: mem[:total],
      processes: mem[:processes],
      atom: mem[:atom],
      binary: mem[:binary],
      code: mem[:code],
      ets: mem[:ets],
      system: mem[:system]
    }
  end

  ## ETS

  defp ets_snapshot do
    Enum.map(@owned_ets, fn {table, label} ->
      case :ets.info(table) do
        :undefined ->
          %{table: table, label: label, exists?: false, size: 0, memory_bytes: 0}

        info ->
          memory_words = Keyword.fetch!(info, :memory)

          %{
            table: table,
            label: label,
            exists?: true,
            size: Keyword.fetch!(info, :size),
            memory_bytes: memory_words * :erlang.system_info(:wordsize),
            owner: Keyword.fetch!(info, :owner)
          }
      end
    end)
  end

  ## Postgres

  defp db_snapshot do
    case Repo.query(
           "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()",
           [],
           timeout: 1_000
         ) do
      {:ok, %{rows: [[active]]}} ->
        %{
          status: :ok,
          active_connections: active,
          pool_size: Repo.config()[:pool_size] || 10
        }

      {:error, _reason} ->
        %{status: :unreachable, active_connections: 0, pool_size: 0}
    end
  rescue
    _ -> %{status: :unreachable, active_connections: 0, pool_size: 0}
  end

  ## Chambers

  defp chamber_snapshot do
    running_pids = Registry.count(Mixwave.Chambers.Registry)
    %{running: running_pids}
  end
end
