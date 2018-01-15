defmodule SpaceEx.StreamConnection do
  use GenServer
  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    StreamUpdate,
  }

  defmodule State do
    @moduledoc false

    @enforce_keys [:socket]
    defstruct(
      socket: nil,
      streams: %{},
      buffer: <<>>,
    )
  end

  def connect!(info, client_id) do
    {:ok, pid} = GenServer.start_link(__MODULE__, [info, client_id])
    pid
  end
    
  def init([info, client_id]) do
    sock = Socket.TCP.connect!(info.host, info.stream_port, packet: :raw)

    request =
      ConnectionRequest.new(type: :STREAM, client_identifier: client_id)
      |> ConnectionRequest.encode

    send_message(sock, request)

    response =
      recv_message(sock)
      |> ConnectionResponse.decode

    case response.status do
      :OK -> sock
      _ -> raise "kRPC streaming connection failed: #{inspect response.message}"
    end

    Socket.active(sock)
    {:ok, %State{socket: sock}}
  end

  defp send_message(sock, message) do
    size =
      byte_size(message)
      |> :gpb.encode_varint

    Socket.Stream.send!(sock, size <> message)
  end

  # Only called during initialisation.
  # After that, the socket is in active mode,
  # and all replies come via handle_info messages.
  defp recv_message(sock, buffer \\ <<>>) do
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

  def register_stream(stream_conn, stream_id, pid) do
    GenServer.call(stream_conn, {:register, stream_id, pid})
  end

  def handle_call({:register, stream_id, pid}, _from, state) do
    streams = state.streams

    if Map.has_key?(streams, stream_id) do
      {:reply, {:error, :already_registered}, state}
    else
      new_streams = Map.put(streams, stream_id, pid)
      {:reply, {:ok, stream_id}, %State{state | streams: new_streams}}
    end
  end

  def handle_info({:tcp, sock, bytes}, %State{socket: sock} = state) do
    buffer =
      (state.buffer <> bytes)
      |> dispatch_updates(state.streams)

    {:noreply, %State{state | buffer: buffer}}
  end

  defp dispatch_updates(buffer, streams) do
    case extract_reply(buffer) do
      {:ok, bytes, new_buffer} ->
        StreamUpdate.decode(bytes) |> process_stream_update(streams)
        new_buffer

      {:error, :incomplete} -> buffer
    end
  end

  defp process_stream_update(update, streams) do
    Enum.each(update.results, &dispatch_stream_result(&1, streams))
  end

  defp dispatch_stream_result(stream_result, streams) do
    id = stream_result.id
    case Map.get(streams, id) do
      nil -> :error # TODO: unregister stream
      pid when is_pid(pid) -> send(pid, {:stream_result, id, stream_result.result})
    end
  end

  defp extract_reply(buffer) do
    case safe_decode_varint(buffer) do
      {size, leftover} ->
        case leftover do
          <<reply :: bytes-size(size), buffer :: binary>> ->
            {:ok, reply, buffer}

          _ -> {:error, :incomplete}
        end

      nil -> {:error, :incomplete}
    end
  end

  defp safe_decode_varint(bytes) do
    if has_varint?(bytes) do
      :gpb.decode_varint(bytes)
    else
      nil
    end
  end

  defp has_varint?(<<>>), do: false
  defp has_varint?(<<0 :: size(1), _ :: bitstring>>), do: true # high bit unset, varint complete
  defp has_varint?(<<1 :: size(1), _ :: size(7), rest :: bitstring>>), do: has_varint?(rest) # high bit set, varint incomplete
end
