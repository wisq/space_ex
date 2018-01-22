defmodule SpaceEx.StreamTest do
  use ExUnit.Case
  require SpaceEx.Stream
  alias SpaceEx.{Stream, Protobufs, KRPC}

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureCall,
    ProcedureResult,
    Request,
    Response
  }

  import SpaceEx.ConnectionHelper, only: [send_message: 2]

  defmodule MockConnection do
    use GenServer
    import SpaceEx.ConnectionHelper
    alias SpaceEx.{Connection, StreamConnection}

    def start do
      # {:ok, pid} = start_supervised(__MODULE__)
      {:ok, conn_pid} = start_link(nil)

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

    def handle_cast({:create_stream_connection, port, client_id}, state) do
      info = %Connection.Info{stream_port: port}
      pid = StreamConnection.connect!(info, client_id, self())
      {:noreply, %State{state | stream_pid: pid}}
    end
  end

  test "stream/1 calls KRPC.add_stream with encoded ProcedureCall" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    KRPC.paused(state.conn) |> Stream.stream()

    assert [call] = MockConnection.dump_calls(state.conn)
    assert call.service == "KRPC"
    assert call.procedure == "AddStream"
    assert [arg1, arg2] = call.arguments

    # procedure call argument
    assert proc = ProcedureCall.decode(arg1.value)
    assert proc.service == "KRPC"
    assert proc.procedure == "get_Paused"
    assert proc.arguments == []

    # start: true
    assert arg2.value == <<1>>
  end

  test "stream/1 creates new Stream process that receives stream updates" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 456)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    stream = KRPC.paused(state.conn) |> Stream.stream()

    me = self()

    spawn_link(fn ->
      send(me, {:first, Stream.get(stream, 100)})
      send(me, {:second, Stream.wait(stream, 100)})
      send(me, {:third, Stream.wait(stream, 100)})
    end)

    true_result = ProcedureResult.new(value: <<1>>)
    false_result = ProcedureResult.new(value: <<0>>)

    send_stream_result(state.stream_socket, 456, true_result)
    assert_receive({:first, true})
    send_stream_result(state.stream_socket, 456, false_result)
    assert_receive({:second, false})
    send_stream_result(state.stream_socket, 456, true_result)
    assert_receive({:third, true})
  end

  def send_stream_result(socket, id, result) do
    StreamUpdate.new(results: [StreamResult.new(id: id, result: result)])
    |> StreamUpdate.encode()
    |> send_message(socket)
  end
end
