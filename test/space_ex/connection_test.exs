defmodule SpaceEx.ConnectionTest do
  use ExUnit.Case, async: true
  alias SpaceEx.Connection

  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    Request,
    Response,
    ProcedureResult
  }

  defmodule BackgroundConnection do
    use GenServer
    alias SpaceEx.Connection

    def start_link(_args) do
      GenServer.start_link(__MODULE__, [])
    end

    def connect(pid, opts) do
      GenServer.cast(pid, {:connect, self(), opts})
    end

    def call_rpc(pid, service, procedure, args) do
      GenServer.cast(pid, {:call_rpc, self(), service, procedure, args})
    end

    def init([]) do
      {:ok, nil}
    end

    def handle_cast({:connect, reply_pid, opts}, _state) do
      conn = Connection.connect!(opts)
      send(reply_pid, {:connected, conn})
      {:noreply, conn}
    end

    def handle_cast({:call_rpc, reply_pid, service, procedure, args}, conn) do
      spawn_link(fn ->
        value = Connection.call_rpc(conn, service, procedure, args)
        send(reply_pid, {:called, value})
      end)

      {:noreply, conn}
    end
  end

  @localhost {127, 0, 0, 1}

  def assert_receive_message(socket) do
    assert_receive {:tcp, ^socket, bytes}
    assert [size | message] = bytes
    assert length(message) == size
    :binary.list_to_bin(message)
  end

  def send_message(message, socket) do
    :ok = :gen_tcp.send(socket, [byte_size(message) | :binary.bin_to_list(message)])
  end

  setup do
    {:ok, rpc_listener} = :gen_tcp.listen(0, ip: @localhost)
    {:ok, rpc_port} = :inet.port(rpc_listener)

    {:ok, stream_listener} = :gen_tcp.listen(0, ip: @localhost)
    {:ok, stream_port} = :inet.port(stream_listener)

    {:ok, bg_conn} = start_supervised(BackgroundConnection)

    BackgroundConnection.connect(
      bg_conn,
      name: "test connection",
      port: rpc_port,
      stream_port: stream_port
    )

    client_id = Enum.map(1..16, fn _ -> Enum.random(1..255) end) |> :binary.list_to_bin()

    [rpc_socket, stream_socket] =
      [
        {rpc_listener, :RPC},
        {stream_listener, :STREAM}
      ]
      |> Enum.map(fn {listener, request_type} ->
        {:ok, socket} = :gen_tcp.accept(listener, 500)

        assert request = assert_receive_message(socket) |> ConnectionRequest.decode()
        assert request.type == request_type

        if request_type == :RPC do
          assert request.client_name == "test connection"
        else
          assert request.client_identifier == client_id
        end

        ConnectionResponse.new(status: :OK, client_identifier: client_id)
        |> ConnectionResponse.encode()
        |> send_message(socket)

        socket
      end)

    assert_receive {:connected, conn}
    assert conn.client_id == client_id

    {:ok,
     [
       conn: conn,
       bg_conn: bg_conn,
       rpc_socket: rpc_socket,
       stream_socket: stream_socket
     ]}
  end

  test "connect!/1", state do
    assert %Connection{} = state.conn
  end

  test "call_rpc/4", state do
    BackgroundConnection.call_rpc(state.bg_conn, "SomeService", "SomeProcedure", ["arg1", "arg2"])

    assert request = assert_receive_message(state.rpc_socket) |> Request.decode()
    assert [call] = request.calls

    assert call.service == "SomeService"
    assert call.procedure == "SomeProcedure"
    assert [arg1, arg2] = call.arguments

    assert arg1.position == 0
    assert arg2.position == 1
    assert arg1.value == "arg1"
    assert arg2.value == "arg2"

    result = ProcedureResult.new(value: "some value")
    response = Response.new(results: [result]) |> Response.encode()

    send_message(response, state.rpc_socket)

    assert_receive {:called, {:ok, "some value"}}
  end

  test "call_rpc/4 allows multiple concurrent pipelined requests", state do
    BackgroundConnection.call_rpc(state.bg_conn, "service", "provider", [])
    assert_receive_message(state.rpc_socket)

    BackgroundConnection.call_rpc(state.bg_conn, "service", "provider", [])
    assert_receive_message(state.rpc_socket)

    BackgroundConnection.call_rpc(state.bg_conn, "service", "provider", [])
    assert_receive_message(state.rpc_socket)

    Enum.each([10, 20, 30], fn n ->
      result = ProcedureResult.new(value: <<n + 1, n + 2, n + 3>>)

      Response.new(results: [result])
      |> Response.encode()
      |> send_message(state.rpc_socket)
    end)

    assert_receive {:called, {:ok, <<11, 12, 13>>}}
    assert_receive {:called, {:ok, <<21, 22, 23>>}}
    assert_receive {:called, {:ok, <<31, 32, 33>>}}
  end
end
