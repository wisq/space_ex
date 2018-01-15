defmodule SpaceEx.Stream do
  use GenServer
  alias SpaceEx.Stream

  defmodule State do
    @moduledoc false

    @enforce_keys [:id]
    defstruct(
      id: nil,
      result: nil,
      waitlist: [],
    )
  end

  @enforce_keys [:pid, :decoder]
  defstruct(
    pid: nil,
    decoder: nil,
    getter: nil,
  )

  def create(conn, procedure, opts \\ []) do
    start = opts[:start] || true

    {:ok, stream_obj} = SpaceEx.KRPC.add_stream(conn, procedure, start)
    stream_id = stream_obj.id

    {:ok, pid} = start_link(stream_id)
    SpaceEx.StreamConnection.register_stream(conn, stream_id, pid)

    decoder = fn value ->
      procedure.module.rpc_decode_return_value(procedure.function, value)
    end
    stream = %Stream{pid: pid, decoder: decoder}

    getter = fn -> Stream.get_value(stream) end
    %Stream{stream | getter: getter}
  end

  def start_link(stream_id) do
    GenServer.start_link(__MODULE__, %State{id: stream_id})
  end
    
  def get_value(stream) do
    result = GenServer.call(stream.pid, :get)
    if result.error do
      raise result.error
    else
      stream.decoder.(result.value)
    end
  end

  # If stream has no data yet, add caller to waitlist.
  # We'll notify them when the first value comes in.
  def handle_call(:get, from, %State{result: nil} = state) do
    waitlist = [from | state.waitlist]
    {:noreply, %State{state | waitlist: waitlist}}
  end

  # Otherwise, just send the current result.
  def handle_call(:get, _from, state) do
    {:reply, state.result, state}
  end

  # If this is the first message, also notify waitlist.
  def handle_info({:stream_result, id, result}, %State{id: id, result: nil} = state) do
    Enum.each(state.waitlist, &GenServer.reply(&1, result))

    {:noreply, %State{state | result: result}}
  end

  # Otherwise, just store the result.
  def handle_info({:stream_result, id, result}, %State{id: id} = state) do
    {:noreply, %State{state | result: result}}
  end
end
