defmodule Mixwave.Accounts.Sweeper do
  @moduledoc """
  Background sweeper that deletes anonymous users idle for more than
  24 hours. Runs hourly under the application supervisor.

  This GenServer is the simplest of the three flagship OTP demos in
  the project: kill it on the supervisor LiveView (v2) and the
  supervisor restarts it; it picks its schedule back up on the next
  hour boundary. Crashes here cannot lose data — the work it does is
  idempotent.
  """
  use GenServer
  require Logger

  alias Mixwave.Accounts

  @sweep_interval :timer.hours(1)
  @idle_threshold_hours 24

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run a sweep right now (synchronous). Useful in tests and from the
  supervisor LiveView's "trigger now" button.
  """
  def sweep_now do
    GenServer.call(__MODULE__, :sweep_now)
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{last_run_at: nil, last_deleted: 0}}
  end

  @impl true
  def handle_info(:sweep, state) do
    state = do_sweep(state)
    schedule_sweep()
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    state = do_sweep(state)
    {:reply, {:ok, state.last_deleted}, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp do_sweep(state) do
    deleted = Accounts.sweep_idle_users(@idle_threshold_hours)

    if deleted > 0 do
      Logger.info("AnonSweeper: deleted #{deleted} idle anonymous users")
    end

    %{state | last_run_at: DateTime.utc_now(), last_deleted: deleted}
  end
end
