defmodule Mixchamb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Public ETS counter for chamber-server restart counts. Each
    # `Mixchamb.Chambers.Server.init/1` bumps its slug's entry; the
    # supervisor LV reads it for the per-chamber Restarts column.
    # Initialised here so it exists before the first chamber starts.
    :ets.new(:chamber_restart_counts, [:set, :public, :named_table, write_concurrency: true])

    # Public ETS bucket store for the note-event rate limiter
    # (one row per {scope, user, slug}). Created here so the first
    # incoming LV `note` event finds it ready.
    :ets.new(Mixchamb.RateLimiter.table(), [
      :set,
      :public,
      :named_table,
      write_concurrency: true
    ])

    children = [
      MixchambWeb.Telemetry,
      Mixchamb.Repo,
      {DNSCluster, query: Application.get_env(:mixchamb, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mixchamb.PubSub},
      # Hourly tick deletes anonymous users idle for more than 24 h.
      Mixchamb.Accounts.Sweeper,
      # Hourly tick deletes chambers idle for more than 24 h.
      Mixchamb.Chambers.Sweeper,
      # Looks up per-chamber GenServers by slug.
      {Registry, keys: :unique, name: Mixchamb.Chambers.Registry},
      # Spawns one Mixchamb.Chambers.Server per active chamber. Each
      # holds the chamber's recent-events buffer for join-time replay.
      {DynamicSupervisor, name: Mixchamb.Chambers.Supervisor, strategy: :one_for_one},
      # Counts how many times each supervised process has restarted.
      Mixchamb.RestartWatcher,
      # Subscribes to custom mixchamb telemetry events and rolls up
      # per-process counters for the admin Dashboard. Started early
      # so it never misses an event from a chamber or sweeper.
      Mixchamb.Telemetry.Counters,
      # Subscribes to note_dropped events and rolls up per-user /
      # per-chamber drop counts for the admin Rate limits tab.
      Mixchamb.Telemetry.RateLimitDrops,
      # Tracks who's in the chamber + their selected instrument.
      MixchambWeb.Presence,
      # Start to serve requests, typically the last entry
      MixchambWeb.Endpoint,
      # Auto-Node.connect/1 each peer listed in PEER_NODES env var
      # (used by `make prod-node1` / `prod-node2` for LAN-cluster
      # testing). :ignore + no-op when PEER_NODES is unset.
      Mixchamb.PeerConnector,
      # Graceful-shutdown coordinator. Listed LAST so it's the
      # FIRST process terminated when SIGTERM arrives — see the
      # module docstring for the full sequence.
      Mixchamb.Drain
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mixchamb.Supervisor]

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
    MixchambWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
