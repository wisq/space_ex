defmodule SpaceEx.Stream do
  use GenServer
  @moduledoc false

  defmodule State do
    @moduledoc false

    @enforce_keys [:id]
    defstruct(
      id: nil,
      result: nil,
      waitlist: [],
    )
  end


  def start_link(stream_id) do
    GenServer.start_link(__MODULE__, %State{id: stream_id})
  end
    
  def get_value(pid) do
    result = GenServer.call(pid, :get)
    if result.error do
      raise result.error
    else
      result.value
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
