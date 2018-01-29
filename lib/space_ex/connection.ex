defmodule SpaceEx.Connection do
  use GenServer
  import SpaceEx.Util.Connection
  alias SpaceEx.{Connection, StreamConnection}

  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    ProcedureCall,
    Argument,
    Request,
    Response
  }

  defmodule RPCError do
    defexception [:error, :message]

    @moduledoc """
    Thrown if an RPC call fails.

    The `error` field contains the raw error object, including server-side backtrace.
    """

    def exception(error) do
      %RPCError{
        error: error,
        message: error.description
      }
    end
  end

  @moduledoc """
  Establishes a connection to a kRPC server.

  This is the first step you'll need in any kRPC program.  Every other call in
  this library depends on having a connection.

  Connections allow pipelining.  Although the kRPC server will only handle one
  request at a time (and will always handle requests in order), multiple
  requests — issued by multiple Elixir processes sharing the same connection —
  can be "on the wire" at any given time.  This dramatically improves
  performance compared to the standard approach of sending a single request and
  waiting until it responds.

  However, be aware that if you issue a call that blocks for a long time, like
  `SpaceEx.SpaceCenter.AutoPilot.wait/2`, it will also block all other RPC
  calls on the same connection until it returns.

  For that reason, if you intend to use blocking calls, but you still want
  other code to continue issuing calls in the mean time, then you should
  consider establishing a separate connection for your blocking calls.
  """

  @enforce_keys [:pid, :stream_pid, :info, :client_id]
  defstruct(
    pid: nil,
    stream_pid: nil,
    info: nil,
    client_id: nil
  )

  defmodule State do
    @moduledoc false

    @enforce_keys [:socket, :client_id]
    defstruct(
      socket: nil,
      client_id: nil,
      stream_pid: nil,
      reply_queue: :queue.new(),
      buffer: <<>>
    )
  end

  defmodule Info do
    @moduledoc """
    Structure containing information about a kRPC connection.

    This can be accessed via `conn.info` from a connection returned by
    `SpaceEx.Connection.connect!/1`, and can also be passed to that function
    instead of raw connection parameters.  The keys and defaults are the same.
    """

    defstruct(
      name: nil,
      host: "127.0.0.1",
      port: 50000,
      stream_port: 50001
    )
  end

  @doc """
  Connects to a kRPC server.

  `info` is either a `SpaceEx.Connection.Info` struct, or a keyword list:

  * `info[:host]` is the target hostname or IP (default: `127.0.0.1`)
  * `info[:port]` is the target port (default: `50000`)
  * `info[:name]` is the client name, displayed in the kRPC status window (default: autogenerated & unique)

  On success, returns `{:ok, conn}` where `conn` is a connection handle that
  can be used as the `conn` argument in RPC calls.  On failure, returns
  `{:error, reason}`.

  The lifecycle of a connection is tied to the process that creates it.  If
  that process exits or crashes, the connection will be shut down.
  """

  def connect(%Info{} = info) do
    # We avoid start_link since otherwise, if `init/1` fails, we get an EXIT signal.
    # Instead, we link to the connection below.
    case GenServer.start(__MODULE__, {info, self()}) do
      {:error, reason} ->
        {:error, reason}

      {:ok, conn_pid} ->
        Process.link(conn_pid)
        details = GenServer.call(conn_pid, :get_details)

        {:ok,
         %Connection{
           pid: conn_pid,
           info: info,
           stream_pid: details.stream_pid,
           client_id: details.client_id
         }}
    end
  end

  def connect(opts), do: struct!(Info, opts) |> connect

  @doc """
  Connects to a kRPC server, or raises on error.

  See `connect/1`.  On success, returns `conn`.
  """
  def connect!(opts_or_info) do
    case connect(opts_or_info) do
      {:ok, conn} -> conn
      {:error, reason} -> raise "kRPC connection failed: #{inspect(reason)}"
    end
  end

  @doc """
  Closes an open connection.

  The associated stream connection will also close.

  Returns `:ok`.
  """
  def close(conn) do
    :ok = GenServer.call(conn.pid, :close)
  end

  @doc false
  @impl true
  def init({info, _launching_pid}) do
    Process.flag(:trap_exit, true)

    establish_rpc_connection(info)
    |> establish_stream_connection(info)
  end

  defp establish_rpc_connection(info) do
    case Socket.TCP.connect(info.host, info.port, packet: :raw) do
      {:ok, socket} ->
        negotiate_rpc_handshake(info, socket)

      {:error, code} ->
        message = :inet.format_error(code)
        {:stop, "#{__MODULE__} failed to connect to #{info.host} port #{info.port}: #{message}"}
    end
  end

  defp negotiate_rpc_handshake(info, socket) do
    ConnectionRequest.new(type: :RPC, client_name: info.name || whoami())
    |> ConnectionRequest.encode()
    |> send_message(socket)

    response =
      recv_message(socket)
      |> ConnectionResponse.decode()

    case response.status do
      :OK ->
        Socket.active(socket)
        client_id = response.client_identifier
        {:ok, %State{socket: socket, client_id: client_id}}

      _ ->
        {:stop, "#{__MODULE__} was rejected by kRPC server: #{response.message}"}
    end
  end

  defp establish_stream_connection({:stop, _} = err, _info), do: err

  defp establish_stream_connection({:ok, state}, info) do
    case StreamConnection.connect(info, state.client_id, self()) do
      {:ok, pid} -> {:ok, %State{state | stream_pid: pid}}
      {:error, message} -> {:stop, message}
    end
  end

  @doc false
  def call_rpc(%Connection{pid: pid}, service, procedure, args) do
    request = encode_rpc_request(service, procedure, args)

    GenServer.call(pid, {:rpc, request}, :infinity)
    |> decode_rpc_response()
  end

  @doc false
  def call_rpc!(conn, service, procedure, args) do
    case call_rpc(conn, service, procedure, args) do
      {:ok, value} -> value
      {:error, error} -> raise RPCError, error
    end
  end

  @doc false
  def cast_rpc(%Connection{pid: pid}, service, procedure, args) do
    request = encode_rpc_request(service, procedure, args)
    GenServer.cast(pid, {:rpc, request})
  end

  defp encode_rpc_request(service, procedure, args) do
    args =
      Enum.with_index(args)
      |> Enum.map(fn {arg, index} ->
        Argument.new(position: index, value: arg)
      end)

    call =
      ProcedureCall.new(
        service: service,
        procedure: procedure,
        arguments: args
      )

    Request.new(calls: [call])
    |> Request.encode()
  end

  defp decode_rpc_response(response) do
    response = Response.decode(response)

    if response.error do
      {:error, response.error}
    else
      [call_reply] = response.results

      if call_reply.error do
        {:error, call_reply.error}
      else
        {:ok, call_reply.value}
      end
    end
  end

  @impl true
  def handle_cast({:rpc, bytes}, state) do
    send_message(bytes, state.socket)
    queue = :queue.in(:noreply, state.reply_queue)

    {:noreply, %State{state | reply_queue: queue}}
  end

  @impl true
  def handle_call({:rpc, bytes}, from, state) do
    send_message(bytes, state.socket)
    queue = :queue.in(from, state.reply_queue)

    {:noreply, %State{state | reply_queue: queue}}
  end

  def handle_call(:get_details, _from, state) do
    details = %{
      client_id: state.client_id,
      stream_pid: state.stream_pid
    }

    {:reply, details, state}
  end

  def handle_call(:client_id, _from, state) do
    {:reply, state.client_id, state}
  end

  def handle_call(:close, from, _state) do
    GenServer.reply(from, :ok)
    exit(:normal)
  end

  @impl true
  def handle_info({:tcp, socket, bytes}, %State{socket: socket} = state) do
    buffer = state.buffer <> bytes
    {queue, buffer} = dispatch_replies(state.reply_queue, buffer)

    {:noreply, %State{state | reply_queue: queue, buffer: buffer}}
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    {:stop, "SpaceEx.Connection socket has closed", state}
  end

  def handle_info({:EXIT, _dead_pid, reason}, _state) do
    # Some linked process -- our Connection and/or its launching process -- has died.
    exit(reason)
  end

  defp dispatch_replies(queue, buffer) do
    case extract_message(buffer) do
      {:ok, reply, new_buffer} ->
        new_queue = dispatch_reply(queue, reply)
        dispatch_replies(new_queue, new_buffer)

      {:error, :incomplete} ->
        {queue, buffer}
    end
  end

  defp dispatch_reply(queue, reply) do
    {{:value, from}, queue} = :queue.out(queue)

    case from do
      :noreply -> :ok
      _ -> GenServer.reply(from, reply)
    end

    queue
  end

  defp whoami do
    os_pid = System.get_pid()
    [_, erlang_pid, _] = inspect(self()) |> String.split(~r/[<>]/)

    "#{os_pid}-#{erlang_pid}"
  end
end
