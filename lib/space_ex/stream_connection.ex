defmodule SpaceEx.StreamConnection do
  use GenServer

  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    StreamUpdate
  }

  @moduledoc false

  defmodule State do
    @moduledoc false

    @enforce_keys [:conn_pid, :socket]
    defstruct(
      conn_pid: nil,
      socket: nil,
      streams: %{},
      buffer: <<>>
    )
  end

  defmodule Registry do
    import Kernel, except: [send: 2]

    @moduledoc false

    def whereis_name({stconn_pid, stream_id}) do
      GenServer.call(stconn_pid, {:whereis, stream_id})
    end

    def register_name({stconn_pid, stream_id}, pid) do
      GenServer.call(stconn_pid, {:register, stream_id, pid})
    end

    def unregister_name({stconn_pid, stream_id}) do
      GenServer.call(stconn_pid, {:unregister, stream_id})
    end

    def send(name, msg), do: whereis_name(name) |> send(msg)
  end

  def connect!(info, client_id, conn_pid) do
    {:ok, pid} = GenServer.start_link(__MODULE__, [info, client_id, conn_pid])
    pid
  end

  def init([info, client_id, conn_pid]) do
    Process.link(conn_pid)
    Process.monitor(conn_pid)

    sock = Socket.TCP.connect!(info.host, info.stream_port, packet: :raw)

    request =
      ConnectionRequest.new(type: :STREAM, client_identifier: client_id)
      |> ConnectionRequest.encode()

    send_message(sock, request)

    response =
      recv_message(sock)
      |> ConnectionResponse.decode()

    case response.status do
      :OK -> sock
      _ -> raise "kRPC streaming connection failed: #{inspect(response.message)}"
    end

    Socket.active(sock)
    {:ok, %State{socket: sock, conn_pid: conn_pid}}
  end

  defp send_message(sock, message) do
    size =
      byte_size(message)
      |> :gpb.encode_varint()

    Socket.Stream.send!(sock, size <> message)
  end

  # Only called during initialisation.
  # After that, the socket is in active mode,
  # and all replies come via handle_info messages.
  defp recv_message(sock, buffer \\ <<>>) do
    case Socket.Stream.recv!(sock, 1) do
      <<1::size(1), _::bitstring>> = byte ->
        # high bit set, varint incomplete
        recv_message(sock, buffer <> byte)

      <<0::size(1), _::bitstring>> = byte ->
        {size, ""} = :gpb.decode_varint(buffer <> byte)
        Socket.Stream.recv!(sock, size)

      nil ->
        raise "kRPC connection closed"
    end
  end

  def handle_call({:whereis, stream_id}, _from, state) do
    {:reply, Map.get(state.streams, stream_id, :undefined), state}
  end

  def handle_call({:register, stream_id, pid}, _from, state) do
    streams = state.streams

    if Map.has_key?(streams, stream_id) do
      {:reply, :no, state}
    else
      new_streams = Map.put(streams, stream_id, pid)
      Process.monitor(pid)
      {:reply, :yes, %State{state | streams: new_streams}}
    end
  end

  def handle_call({:unregister, stream_id}, _from, state) do
    new_streams = Map.delete(state.streams, stream_id)
    {:reply, :ok, %State{state | streams: new_streams}}
  end

  def handle_info({:DOWN, _ref, :process, dead_pid, _reason}, state) do
    if dead_pid == state.conn_pid do
      # Connection has died, so shut ourselves down too.
      exit(:normal)
    else
      new_streams =
        Enum.reject(state.streams, fn {_, pid} ->
          pid == dead_pid
        end)
        |> Map.new()

      {:noreply, %State{state | streams: new_streams}}
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

      {:error, :incomplete} ->
        buffer
    end
  end

  defp process_stream_update(update, streams) do
    Enum.each(update.results, &dispatch_stream_result(&1, streams))
  end

  defp dispatch_stream_result(stream_result, streams) do
    id = stream_result.id

    case Map.get(streams, id) do
      # TODO: unregister stream
      nil ->
        :error

      pid when is_pid(pid) ->
        send(pid, {:stream_result, id, stream_result.result})
    end
  end

  defp extract_reply(buffer) do
    case safe_decode_varint(buffer) do
      {size, leftover} ->
        case leftover do
          <<reply::bytes-size(size), buffer::binary>> ->
            {:ok, reply, buffer}

          _ ->
            {:error, :incomplete}
        end

      nil ->
        {:error, :incomplete}
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
  # high bit unset, varint complete
  defp has_varint?(<<0::size(1), _::bitstring>>), do: true
  # high bit set, varint incomplete
  defp has_varint?(<<1::size(1), _::size(7), rest::bitstring>>), do: has_varint?(rest)
end
