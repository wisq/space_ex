defmodule SpaceEx.Stream do
  use GenServer
  alias SpaceEx.Stream

  @moduledoc """
  Enables data to be streamed as it changes, instead of polled repeatedly.

  Streams are an efficient way to repeatedly retrieve data from the game.

  To set up a stream, you can use `SpaceEx.Stream.stream/2`.

  Alternatively, you can create `SpaceEx.Procedure` that references the
  procedure you want to run, and then pass that to `SpaceEx.Stream.create/2`.

  In most situations where you find yourself asking for the same piece of data
  over and over, you're probably better off using a stream.  This will reduce
  the load on both ends and make your code run faster.

  However, if your code checks the value infrequently (e.g. once per second or
  less), but the value is changing constantly (altitude, current time, etc.),
  you should consider either using polling, or reducing the stream's rate.

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

    @enforce_keys [:id, :conn]
    defstruct(
      id: nil,
      conn: nil,
      result: nil,
      waitlist: [],
    )
  end

  @enforce_keys [:id, :conn, :pid, :decoder]
  defstruct(
    id: nil,
    conn: nil,
    pid: nil,
    decoder: nil,
  )

  @doc """
  Creates a stream, and optionally starts it.

  `procedure` should be a `SpaceEx.Procedure` structure.  The stream's value
  will be the result of calling this procedure over and over (with the same
  arguments each time).

  See the module documentation for usage examples.

  ## Options

  * `:start` — when `false`, the stream is created, but not started.  Default: `start: true`.
  * `:rate` — the stream's update rate, in updates per second.  Default: unlimited.
  """

  def create(procedure, opts \\ []) do
    conn = procedure.conn
    start = opts[:start] || true

    stream = SpaceEx.KRPC.add_stream(conn, procedure, start)

    if rate = opts[:rate] do
      SpaceEx.KRPC.set_stream_rate(conn, stream.id, rate)
    end

    decoder = fn value ->
      procedure.module.rpc_decode_return_value(procedure.function, value)
    end

    launch(conn, stream.id, decoder)
  end

  # Used by both Stream and Event.
  @doc false
  def launch(conn, stream_id, decoder) do
    {:ok, pid} = start_link(conn, stream_id)
    SpaceEx.StreamConnection.register_stream(conn, stream_id, pid)

    %Stream{id: stream_id, conn: conn, pid: pid, decoder: decoder}
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

  defmacro stream(function_call, opts \\ []) do
    quote do
      require SpaceEx.Procedure
      SpaceEx.Procedure.create(unquote(function_call))
      |> SpaceEx.Stream.create(unquote(opts))
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

  defmacro stream_fn(function_call, opts \\ []) do
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
      raise result.error.description
    else
      stream.decoder.(result.value)
    end
  end

  @doc """
  Wait for the stream value to change.

  This will wait until a new stream value is received, then retrieve it and
  decode it.  It will block for up to `timeout` milliseconds (default:
  forever, aka `:infinity`), after which it will throw an `exit` signal.

  You can technically catch this exit signal with `try ... catch :exit, _`,
  but it's not generally considered good practice to do so.  As such, `wait/2`
  timeouts should generally be reserved for "something has gone badly wrong".

  ## Example

  ```elixir
  paused = SpaceEx.SpaceCenter.get_paused(conn) |> SpaceEx.Stream.stream

  SpaceEx.Stream.wait(paused)  # returns true/false the next time you un/pause
  ```
  """

  def wait(stream, timeout \\ :infinity) do
    result = GenServer.call(stream.pid, :wait, timeout)
    if result.error do
      raise result.error.description
    else
      stream.decoder.(result.value)
    end
  end

  @doc """
  Set the update rate of a stream.

  `rate` is the number of updates per second.  Setting the rate to `0` or `nil`
  will remove all rate limiting and update as often as possible.
  """

  def set_rate(stream, rate) do
    SpaceEx.KRPC.set_stream_rate(stream.conn, stream.stream_id, rate || 0)
  end

  @doc false
  def start_link(conn, stream_id) do
    GenServer.start_link(__MODULE__, %State{id: stream_id, conn: conn})
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

  def handle_call(:wait, from, state) do
    waitlist = [from | state.waitlist]
    {:noreply, %State{state | waitlist: waitlist}}
  end

  def handle_info({:stream_result, id, result}, %State{id: id} = state) do
    if result == state.result do
      {:noreply, state}
    else
      Enum.each(state.waitlist, &GenServer.reply(&1, result))
      {:noreply, %State{state | result: result}}
    end
  end
end
