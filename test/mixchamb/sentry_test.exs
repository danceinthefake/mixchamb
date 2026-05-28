defmodule Mixchamb.SentryTest do
  @moduledoc """
  Proves the Sentry capture pipeline actually works (without sending
  over the network). `config :sentry, test_mode: true` makes
  `Sentry.Test` collect events in-process so we can assert on them.
  """
  use ExUnit.Case, async: false

  setup do
    Sentry.Test.start_collecting_sentry_reports()
    :ok
  end

  test "an explicitly captured exception is reported to Sentry" do
    try do
      raise "boom — sentry verification"
    rescue
      e -> Sentry.capture_exception(e, stacktrace: __STACKTRACE__)
    end

    assert [event] = Sentry.Test.pop_sentry_reports()
    [exception] = event.exception
    assert exception.type == "RuntimeError"
    assert exception.value =~ "boom — sentry verification"
  end

  test "a crashing process is reported via the LoggerHandler" do
    # Mirror the production wiring (application.ex attaches this only
    # when a DSN is set; test_mode has no DSN, so attach it here).
    :logger.add_handler(:sentry_test_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    on_exit(fn -> :logger.remove_handler(:sentry_test_handler) end)

    {:ok, pid} =
      Task.start(fn ->
        raise "crash — sentry verification"
      end)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000

    # Give the logger handler a beat to forward the crash report.
    reports = wait_for_reports()

    assert Enum.any?(reports, fn e ->
             Enum.any?(e.exception || [], &(&1.value =~ "crash — sentry verification"))
           end)
  end

  defp wait_for_reports(tries \\ 20) do
    reports = Sentry.Test.pop_sentry_reports()

    cond do
      reports != [] ->
        reports

      tries == 0 ->
        []

      true ->
        Process.sleep(25)
        wait_for_reports(tries - 1)
    end
  end
end
