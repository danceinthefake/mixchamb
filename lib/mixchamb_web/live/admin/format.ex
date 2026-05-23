defmodule MixchambWeb.Admin.Format do
  @moduledoc """
  Shared display helpers for the admin LiveViews. Pulled out
  because six different admin pages were each defining their own
  `time_ago/1` variant — same intent, slightly different
  `nil`-handling, easy to drift. One module, one definition.

  Import this in admin LVs that need to render relative
  timestamps:

      import MixchambWeb.Admin.Format
  """

  @doc """
  Humanises a UTC timestamp into a relative-time string. Accepts
  both `DateTime` and `NaiveDateTime` (the DB sometimes hands back
  the latter via `select_merge`). Two-arity variant lets the
  caller pick the nil fallback — default is `"—"`, but pages
  like SweepersLive want `"never"` when a job hasn't run yet.
  """
  def time_ago(value, fallback \\ "—")

  def time_ago(nil, fallback), do: fallback

  def time_ago(%DateTime{} = dt, _fallback) do
    DateTime.utc_now()
    |> DateTime.diff(dt, :second)
    |> humanise_seconds()
  end

  def time_ago(%NaiveDateTime{} = ndt, fallback) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> time_ago(fallback)
  end

  @doc """
  Same shape as `time_ago/1`, but the input is a monotonic
  millisecond timestamp (`System.monotonic_time(:millisecond)`).
  Used by the rate-limits page where bucket reset-at timestamps
  are stored that way for cheap comparison.
  """
  def time_ago_ms(nil), do: "—"

  def time_ago_ms(t) when is_integer(t) do
    now = System.monotonic_time(:millisecond)
    seconds = div(now - t, 1000)
    humanise_seconds(seconds)
  end

  # Clock skew (negative) or sub-5-second freshness both read as
  # "just now"; saying "2s ago" feels twitchy on a 1 s tick.
  defp humanise_seconds(seconds) when seconds < 5, do: "just now"
  defp humanise_seconds(seconds) when seconds < 60, do: "#{seconds}s ago"
  defp humanise_seconds(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp humanise_seconds(seconds) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp humanise_seconds(seconds), do: "#{div(seconds, 86_400)}d ago"
end
