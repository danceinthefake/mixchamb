defmodule Mixwave.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MixwaveWeb.Telemetry,
      Mixwave.Repo,
      {DNSCluster, query: Application.get_env(:mixwave, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mixwave.PubSub},
      # Hourly tick deletes anonymous users idle for more than 24 h.
      Mixwave.Accounts.Sweeper,
      # Holds recent note events for join-time replay.
      Mixwave.Studio.Room,
      # Counts how many times each supervised process has restarted.
      Mixwave.Studio.RestartWatcher,
      # Tracks who's in the studio + their selected instrument.
      MixwaveWeb.Presence,
      # Start to serve requests, typically the last entry
      MixwaveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mixwave.Supervisor]
    children =
      children ++
        if(Application.get_env(:live_vue, :ssr_module) == LiveVue.SSR.QuickBEAM,
          do: [LiveVue.SSR.QuickBEAM],
          else: []
        )

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MixwaveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
