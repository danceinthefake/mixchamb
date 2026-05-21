defmodule Mixchamb.PeerConnector do
  @moduledoc """
  Connects this node to a comma-separated list of peer nodes from
  the `PEER_NODES` env var on startup, retrying until each peer is
  reachable. Used by the LAN-cluster Makefile targets so two release
  nodes form a BEAM cluster without a manual `Node.connect/1` from
  a remote shell.

  No-op when `PEER_NODES` is empty or unset, which is the case on
  Fly (where `dns_cluster` discovers peers via private DNS instead).
  """
  # :transient — once we've connected (or given up), we exit :normal
  # and the supervisor must not restart us. Default :permanent would
  # restart on :normal exit, loop forever, hit max_restarts, and tear
  # down the whole supervision tree.
  use GenServer, restart: :transient

  require Logger

  @retry_ms 1_000
  @max_attempts 60

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    case parse_peers(System.get_env("PEER_NODES")) do
      [] ->
        :ignore

      peers ->
        send(self(), {:try, peers, 1})
        {:ok, %{}}
    end
  end

  @impl true
  def handle_info({:try, peers, attempt}, state) do
    remaining =
      Enum.reject(peers, fn peer ->
        if Node.connect(peer) == true do
          Logger.info("PeerConnector: connected to #{peer}")
          true
        else
          false
        end
      end)

    cond do
      remaining == [] ->
        {:stop, :normal, state}

      attempt >= @max_attempts ->
        Logger.warning(
          "PeerConnector: giving up on #{inspect(remaining)} after #{attempt} attempts"
        )

        {:stop, :normal, state}

      true ->
        Process.send_after(self(), {:try, remaining, attempt + 1}, @retry_ms)
        {:noreply, state}
    end
  end

  defp parse_peers(nil), do: []

  defp parse_peers(raw) do
    raw
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end
end
