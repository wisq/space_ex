defmodule SpaceEx.PipeliningConnection do
  use GenServer
  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    ProcedureCall,
    Request,
    Response,
  }

  defmodule State do
    @enforce_keys [:socket, :reply_queue]
    defstruct(
      socket: nil,
      reply_queue: nil,
      buffer: <<>>,
    )
  end

  def connect!(host, port) do
    {:ok, pid} = GenServer.start_link(__MODULE__, [host, port])
    pid
  end
    
  def init([host, port]) do
    sock = Socket.TCP.connect!(host, port, packet: :raw)

    request =
      ConnectionRequest.new(type: :RPC, client_name: "test-client-1")
      |> ConnectionRequest.encode

    send_message(sock, request)

    response =
      recv_message(sock)
      |> ConnectionResponse.decode

    case response.status do
      :OK -> sock
      _ -> raise "kRPC connection failed: #{inspect response.message}"
    end

    Socket.active(sock)
    {:ok, %State{
      socket: sock,
      reply_queue: :queue.new,
    }}
  end

  def send_message(sock, message) do
    size =
      byte_size(message)
      |> :gpb.encode_varint

    Socket.Stream.send!(sock, size <> message)
  end

  # Only called during initialisation.
  # After that, the socket is in active mode,
  # and all replies come via handle_info messages.
  def recv_message(sock, buffer \\ <<>>) do
    case Socket.Stream.recv!(sock, 1) do
      <<1 :: size(1), _ :: bitstring>> = byte ->
        # high bit set, varint incomplete
        recv_message(sock, buffer <> byte)

      <<0 :: size(1), _ :: bitstring>> = byte ->
        {size, ""} = :gpb.decode_varint(buffer <> byte)
        Socket.Stream.recv!(sock, size)

      nil -> raise "kRPC connection closed"
    end
  end

  def call_rpc(pid, service, procedure) do # TODO: args
    call = ProcedureCall.new(
      service: service,
      procedure: procedure,
      arguments: [],
    )

    request =
      Request.new(calls: [call])
      |> Request.encode

    response =
      GenServer.call(pid, {:rpc, request})
      |> Response.decode

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

  def handle_call({:rpc, bytes}, from, state) do
    send_message(state.socket, bytes)
    queue = :queue.in(from, state.reply_queue)

    {:noreply, %State{state | reply_queue: queue}}
  end

  def handle_info({:tcp, sock, bytes}, %State{socket: sock} = state) do
    buffer = state.buffer <> bytes
    {queue, buffer} = dispatch_replies(state.reply_queue, buffer)

    {:noreply, %State{state |
      reply_queue: queue,
      buffer: buffer,
    }}
  end

  def dispatch_replies(queue, buffer) do
    case extract_reply(buffer) do
      {:ok, reply, new_buffer} ->
        new_queue = dispatch_reply(queue, reply)
        dispatch_replies(new_queue, new_buffer)

      {:error, :incomplete} -> {queue, buffer}
    end
  end

  def dispatch_reply(queue, reply) do
    {{:value, from}, queue} = :queue.out(queue)
    GenServer.reply(from, reply)
    queue
  end

  def extract_reply(buffer) do
    case safe_decode_varint(buffer) do
      {size, leftover} ->
        if byte_size(leftover) >= size do
          reply  = binary_part(leftover, 0, size)
          buffer = binary_part(leftover, size, byte_size(leftover) - size)
          {:ok, reply, buffer}
        else
          {:error, :incomplete}
        end

      nil -> {:error, :incomplete}
    end
  end

  def safe_decode_varint(bytes) do
    if has_varint?(bytes) do
      :gpb.decode_varint(bytes)
    else
      nil
    end
  end

  def has_varint?(<<>>), do: false
  def has_varint?(<<0 :: size(1), _ :: bitstring>>), do: true # high bit unset, varint complete
  def has_varint?(<<1 :: size(1), _ :: size(7), rest :: bitstring>>), do: has_varint?(rest) # high bit set, varint incomplete
end
