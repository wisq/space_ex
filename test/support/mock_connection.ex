defmodule SpaceEx.Test.MockConnection do
  use GenServer

  alias SpaceEx.{Connection, StreamConnection}

  alias SpaceEx.Protobufs.{
    ProcedureResult,
    Request,
    Response
  }

  import SpaceEx.Test.ConnectionHelper
  import ExUnit.Callbacks

  def start do
    {:ok, conn_pid} = start_supervised(__MODULE__, restart: :temporary)

    # Establish StreamConnection:
    state = start_stream_listener()
    GenServer.cast(conn_pid, {:create_stream_connection, state.stream_port, state.client_id})
    state = accept_stream(state)

    stream_pid = GenServer.call(conn_pid, :get_stream_pid)

    Map.put(state, :conn, %SpaceEx.Connection{
      pid: conn_pid,
      stream_pid: stream_pid,
      info: nil,
      client_id: state.client_id
    })
  end

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, [])
  end

  def add_reply(reply, conn) do
    GenServer.call(conn.pid, {:add_replies, [reply]}, 100)
  end

  def add_result_value(value, conn) do
    result = ProcedureResult.new(value: value)

    Response.new(results: [result])
    |> Response.encode()
    |> add_reply(conn)
  end

  def dump_requests(conn) do
    GenServer.call(conn.pid, :dump_requests, 100)
    |> Enum.map(&Request.decode/1)
  end

  def dump_calls(conn) do
    dump_requests(conn)
    |> Enum.map(& &1.calls)
    |> List.flatten()
  end

  def close(conn) do
    GenServer.call(conn.pid, :close, 100)
  end

  defmodule State do
    defstruct(requests: [], replies: [], stream_pid: nil)
  end

  def init([]) do
    {:ok, %State{}}
  end

  def handle_call({:rpc, _bytes}, _from, %State{replies: []}) do
    raise "Got RPC request, but no replies in queue"
  end

  def handle_call({:rpc, bytes}, _from, %State{replies: [next_reply | future_replies]} = state) do
    {:reply, next_reply,
     %State{state | requests: state.requests ++ [bytes], replies: future_replies}}
  end

  def handle_call(:dump_requests, _from, state) do
    {:reply, state.requests, %State{state | requests: []}}
  end

  def handle_call({:add_replies, replies}, _from, state) do
    {:reply, :ok, %State{state | replies: state.replies ++ replies}}
  end

  def handle_call(:get_stream_pid, _from, state) do
    {:reply, state.stream_pid, state}
  end

  def handle_call(:close, from, _state) do
    GenServer.reply(from, :ok)
    exit(:normal)
  end

  def handle_cast({:create_stream_connection, port, client_id}, state) do
    info = %Connection.Info{stream_port: port}
    {:ok, pid} = StreamConnection.connect(info, client_id, self())
    {:noreply, %State{state | stream_pid: pid}}
  end
end
