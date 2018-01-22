defmodule SpaceEx.ConnectionHelper do
  :ok = Application.ensure_started(:ex_unit)
  import ExUnit.{Assertions, Callbacks}
  alias SpaceEx.Connection

  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse
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

  def setup_connection do
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

    [
      conn: conn,
      bg_conn: bg_conn,
      rpc_socket: rpc_socket,
      stream_socket: stream_socket
    ]
  end
end
