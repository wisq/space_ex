defmodule SpaceEx.Test.ConnectionHelper do
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

    def shutdown(pid) do
      GenServer.call(pid, :shutdown)
    end

    def init([]) do
      {:ok, nil}
    end

    def handle_cast({:connect, reply_pid, opts}, _state) do
      try do
        conn = Connection.connect!(opts)
        send(reply_pid, {:connected, conn})
        {:noreply, conn}
      rescue
        error ->
          send(reply_pid, {:connect_error, error})
          {:noreply, nil}
      end
    end

    def handle_cast({:call_rpc, reply_pid, service, procedure, args}, conn) do
      spawn_link(fn ->
        value = Connection.call_rpc(conn, service, procedure, args)
        send(reply_pid, {:called, value})
      end)

      {:noreply, conn}
    end

    def handle_call(:shutdown, from, _state) do
      GenServer.reply(from, :ok)
      exit(:normal)
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

  def start_connection do
    {:ok, rpc_listener} = :gen_tcp.listen(0, ip: @localhost)
    {:ok, rpc_port} = :inet.port(rpc_listener)

    {:ok, stream_listener} = :gen_tcp.listen(0, ip: @localhost)
    {:ok, stream_port} = :inet.port(stream_listener)

    {:ok, bg_conn} = start_supervised(BackgroundConnection, restart: :temporary)
    # Or, for debugging:
    # {:ok, bg_conn} = BackgroundConnection.start_link(nil)

    BackgroundConnection.connect(
      bg_conn,
      name: "test connection",
      port: rpc_port,
      stream_port: stream_port
    )

    client_id = Enum.map(1..16, fn _ -> Enum.random(1..255) end) |> :binary.list_to_bin()

    %{
      bg_conn: bg_conn,
      rpc_listener: rpc_listener,
      stream_listener: stream_listener,
      client_id: client_id
    }
  end

  def start_stream_listener do
    {:ok, stream_listener} = :gen_tcp.listen(0, ip: @localhost)
    {:ok, stream_port} = :inet.port(stream_listener)

    %{
      stream_listener: stream_listener,
      stream_port: stream_port,
      client_id: "bogus"
    }
  end

  def accept_rpc(state, response \\ nil) do
    response = response || ConnectionResponse.new(status: :OK, client_identifier: state.client_id)

    socket = accept_client(:RPC, state.rpc_listener, state.client_id, response)

    Map.put(state, :rpc_socket, socket)
  end

  def accept_stream(state, response \\ nil) do
    response = response || ConnectionResponse.new(status: :OK)

    socket = accept_client(:STREAM, state.stream_listener, state.client_id, response)

    Map.put(state, :stream_socket, socket)
  end

  def assert_connected(state) do
    assert_receive {:connected, conn}
    assert conn.client_id == state.client_id

    Map.put(state, :conn, conn)
  end

  defp accept_client(request_type, listener, client_id, response) do
    {:ok, socket} = :gen_tcp.accept(listener, 500)

    assert request = assert_receive_message(socket) |> ConnectionRequest.decode()
    assert request.type == request_type

    if request_type == :RPC do
      assert request.client_name == "test connection"
    else
      assert request.client_identifier == client_id
    end

    response
    |> ConnectionResponse.encode()
    |> send_message(socket)

    socket
  end
end
