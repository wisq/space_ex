defmodule SpaceEx.StreamConnection do
  use GenServer
  import SpaceEx.Util.Connection
  alias SpaceEx.Connection.Info
  alias SpaceEx.Stream

  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    StreamUpdate
  }

  @moduledoc false

  defmodule State do
    @moduledoc false

    @enforce_keys [:socket]
    defstruct(
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

  def connect(info, client_id, conn_pid) do
    GenServer.start_link(__MODULE__, [info, client_id, conn_pid])
  end

  def init([info, client_id, conn_pid]) do
    Process.link(conn_pid)
    Process.flag(:trap_exit, true)

    establish_stream_connection(info, client_id)
  end

  defp establish_stream_connection(info, client_id) do
    case :gen_tcp.connect(Info.host_arg(info), info.stream_port, connection_options()) do
      {:ok, socket} ->
        negotiate_stream_handshake(client_id, socket)

      {:error, code} ->
        message = :inet.format_error(code)

        {:stop,
         "#{__MODULE__} failed to connect to #{info.host} port #{info.stream_port}: #{message}"}
    end
  end

  defp negotiate_stream_handshake(client_id, socket) do
    ConnectionRequest.new(type: :STREAM, client_identifier: client_id)
    |> ConnectionRequest.encode()
    |> send_message(socket)

    response =
      recv_message(socket)
      |> ConnectionResponse.decode()

    case response.status do
      :OK ->
        :inet.setopts(socket, active: true)
        {:ok, %State{socket: socket}}

      _ ->
        {:stop, "#{__MODULE__} was rejected by kRPC server: #{response.message}"}
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
    new_streams =
      Enum.reject(state.streams, fn {_, pid} ->
        pid == dead_pid
      end)
      |> Map.new()

    {:noreply, %State{state | streams: new_streams}}
  end

  def handle_info({:tcp, socket, bytes}, %State{socket: socket} = state) do
    buffer =
      (state.buffer <> bytes)
      |> dispatch_updates(state.streams)

    {:noreply, %State{state | buffer: buffer}}
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    {:stop, "SpaceEx.StreamConnection socket has closed", state}
  end

  def handle_info({:EXIT, _dead_pid, reason}, _state) do
    # Some linked process -- our Connection and/or its launching process -- has died.
    exit(reason)
  end

  defp dispatch_updates(buffer, streams) do
    case extract_message(buffer) do
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
        result = Stream.package_result(stream_result.result)
        send(pid, {:stream_result, id, result})
    end
  end
end
