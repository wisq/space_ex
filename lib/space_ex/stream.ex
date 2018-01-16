defmodule SpaceEx.Stream do
  use GenServer
  alias SpaceEx.Stream

  @moduledoc """
  Enables data to be streamed as it changes, instead of polled repeatedly.

  Streams are an efficient way to repeatedly retrieve data from the game.

  To set up a stream, you can use `SpaceEx.Stream.stream/2`.

  Alternatively, you can create `SpaceEx.Procedure` that references the
  procedure you want to run, and then pass that to `SpaceEx.Stream.create`.

  In most situations where you find yourself asking for the same piece of data
  over and over, you're probably better off using a stream.  This will reduce
  the load on both ends and make your code run faster.

  Example usage:

  ```elixir
  require SpaceEx.Procedure
  stream =
    SpaceEx.SpaceCenter.get_ut(conn)
    |> SpaceEx.Procedure.call
    |> SpaceEx.Stream.create(start: true)

  SpaceEx.Stream.get(stream)  # 83689.09043863538
  Process.sleep(100)
  SpaceEx.Stream.get(stream)  # 83689.1904386354
  Process.sleep(100)
  SpaceEx.Stream.get(stream)  # 83689.29043863542

  # You can also create a nifty "magic variable" shorthand:
  ut = SpaceEx.Stream.get_fn(stream)

  ut.()  # 83689.29043863544
  Process.sleep(100)
  ut.()  # 83689.39043863546
  Process.sleep(100)
  ut.()  # 83689.49043863548

  # You can even create both the stream and the shortcut at once:
  {stream, ut} =
    SpaceEx.SpaceCenter.get_ut(conn)
    |> SpaceEx.Stream.stream

  SpaceEx.Stream.get(stream)  # 83689.09043863540
  ut.()  # 83689.49043863541
  ```
  """

  defmodule State do
    @moduledoc false

    @enforce_keys [:id]
    defstruct(
      id: nil,
      result: nil,
      waitlist: [],
    )
  end

  @enforce_keys [:id, :pid, :decoder]
  defstruct(
    id: nil,
    pid: nil,
    decoder: nil,
  )

  @doc """
  Creates a stream, and optionally starts it.

  `procedure` should be a `SpaceEx.Procedure` structure generated using
  `SpaceEx.Procedure.call/1`.  The stream's value will be the result of calling
  this function over and over (with the same arguments each time).

  See the module documentation for usage examples.

  ## Options

  * `:start` — when `false`, the stream is created, but not started.  The default is `start: true`.
  """

  def create(procedure, opts \\ []) do
    conn = procedure.conn
    start = opts[:start] || true

    {:ok, stream_obj} = SpaceEx.KRPC.add_stream(conn, procedure, start)
    stream_id = stream_obj.id

    {:ok, pid} = start_link(stream_id)
    SpaceEx.StreamConnection.register_stream(conn, stream_id, pid)

    decoder = fn value ->
      procedure.module.rpc_decode_return_value(procedure.function, value)
    end
    %Stream{id: stream_id, pid: pid, decoder: decoder}
  end

  @doc """
  Creates a stream directly from function call syntax.

  This is equivalent to calling `SpaceEx.Procedure.create/1` and `SpaceEx.Stream.create/2`.

  ## Example

  ```elixir
  stream =
    SpaceEx.SpaceCenter.Flight.get_mean_altitude(conn, flight)
    |> SpaceEx.Stream.create

  SpaceEx.Stream.get(stream)  # 76.64177794696297
  ```
  """

  defmacro stream(function_call, opts) do
    quote do
      SpaceEx.Procedure.create(unquote(function_call))
      |> SpaceEx.Stream.new(unquote(opts))
    end
  end

  @doc """
  Creates a stream and query function directly from function call syntax.

  This is equivalent to calling `SpaceEx.Procedure.create/1`,
  `SpaceEx.Stream.create/2`, and `SpaceEx.Stream.get_fn/1`, all in sequence.

  Returns a tuple containing the stream and the getter function.

  ## Example

  ```elixir
  {stream, altitude} =
    SpaceEx.SpaceCenter.Flight.get_mean_altitude(conn, flight)
    |> SpaceEx.Stream.stream_fn

  altitude.() |> IO.inspect  # 76.64177794696297
  ```
  """

  defmacro stream_fn(function_call, opts) do
    quote do
      stream = SpaceEx.Stream.stream(unquote(function_call), unquote(opts))

      {stream, SpaceEx.Stream.get_fn(stream)}
    end
  end

  @doc """
  Returns an anonymous function that can be used to query the stream.

  This function can make code cleaner, by emulating a sort of "magic variable"
  that constantly updates itself to the current value.  For example, if you
  assign `apoapsis = SpaceEx.Stream.get_fn(apo_stream)`, you can now use
  `apoapsis.()` to get the up-to-date value at any time.
  """

  def get_fn(stream) do
    fn -> get(stream) end
  end

  @doc """
  Get (and decode) the current value from a stream.

  This will retrieve the latest stream value and decode it.  (Because streams
  can receive hundreds of updates every second, stream values are not decoded
  until requested.)

  Note that if a stream has not received any data yet, this function will block
  for up to `timeout` milliseconds (default: 5 seconds) for the first
  value to arrive.

  A timeout usually indicates that the stream was created with `start: false`,
  and it was not subsequently started before the timeout expired.
  """
    
  def get(stream, timeout \\ 5000) do
    result = GenServer.call(stream.pid, :get, timeout)
    if result.error do
      raise result.error
    else
      stream.decoder.(result.value)
    end
  end

  @doc false
  def start_link(stream_id) do
    GenServer.start_link(__MODULE__, %State{id: stream_id})
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
