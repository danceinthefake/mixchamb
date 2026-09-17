defmodule Mixchamb.PeerConnectorTest do
  use ExUnit.Case, async: false

  alias Mixchamb.PeerConnector

  setup do
    prev = System.get_env("PEER_NODES")

    on_exit(fn ->
      if prev, do: System.put_env("PEER_NODES", prev), else: System.delete_env("PEER_NODES")
    end)

    :ok
  end

  test "no PEER_NODES → :ignore" do
    System.delete_env("PEER_NODES")
    assert PeerConnector.start_link([]) == :ignore
    System.put_env("PEER_NODES", " , ")
    assert PeerConnector.start_link([]) == :ignore
  end

  test "unreachable peers retry then the loop is driven by :try messages" do
    System.put_env("PEER_NODES", "ghost@nowhere, other@nowhere")
    {:ok, pid} = PeerConnector.start_link([])
    ref = Process.monitor(pid)

    # First attempt fails for both (no such nodes) → reschedules.
    assert %{} = :sys.get_state(pid)

    # Fast-forward: pretend we're on the last attempt → gives up, exits :normal.
    send(pid, {:try, [:ghost@nowhere], 60})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end

  test "all peers connected → stops normally" do
    System.put_env("PEER_NODES", "ghost@nowhere")
    {:ok, pid} = PeerConnector.start_link([])
    ref = Process.monitor(pid)
    # Node.connect(node()) to ourselves returns true when distribution is
    # up; when it's not (plain `mix test`) it's :ignored — either way an
    # empty remaining list stops the server.
    send(pid, {:try, [], 1})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end
end
