defmodule SpaceEx.Stream do
  use GenServer
  alias SpaceEx.Stream
  alias SpaceEx.{KRPC, StreamConnection, Types}

  @moduledoc """
  Enables data to be streamed as it changes, instead of polled repeatedly.

  Streams are an efficient way to repeatedly retrieve data from the game.
  In most situations where you find yourself asking for the same piece of data
  over and over, you're probably better off using a stream.  This will reduce
  the load on both ends and make your code run faster.

  However, if your code checks the value infrequently (e.g. once per second or
  less), but the value is changing constantly (altitude, current time, etc.),
  you should consider either using polling, or reducing the stream's rate.

  ## Creating streams

  To set up a stream, you can use the `SpaceEx.Stream.stream/2` macro to wrap a
  procedure call.

  Alternatively, you can use `SpaceEx.Procedure.create/1` to create a reference
  to the procedure you want to run, and then pass that to
  `SpaceEx.Stream.create/2`.

  ## Stream lifecycle

  Generally, multiple requests to stream the exact same data will be detected
  by the kRPC server, and each request will return the same stream.

  This would ordinarily be a problem for a multi-process environment like
  Erlang. If one process calls `shutdown/1`, it might remove a stream that
  other processes are currently using.

  To prevent this, when you create a stream, you also create a bond between
  that stream and your current process.  Calling `shutdown/1` will break that
  bond, but the stream will only actually shut down if *all* bonded processes
  are no longer alive.

  Streams will also automatically shut down if all bonded processes terminate.

  ## Example usage

  ```elixir
  require SpaceEx.Stream

  stream =
    SpaceEx.SpaceCenter.ut(conn)
    |> SpaceEx.Stream.stream()

  # Equivalent:
  stream =
    SpaceEx.SpaceCenter.ut(conn)
    |> SpaceEx.Procedure.create()
    |> SpaceEx.Stream.create()

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
    |> SpaceEx.Stream.stream_fn()

  SpaceEx.Stream.get(stream)  # 83689.49043863541
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
      bonds: MapSet.new()
    )
  end

  @enforce_keys [:id, :conn, :pid, :decoder]
  defstruct(
    id: nil,
    conn: nil,
    pid: nil,
    decoder: nil
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

    stream = KRPC.add_stream(conn, procedure, start: start)

    if rate = opts[:rate] do
      KRPC.set_stream_rate(conn, stream.id, rate)
    end

    decoder = fn value ->
      Types.decode(value, procedure.return_type, conn)
    end

    launch(conn, stream.id, decoder)
  end

  # Used by both Stream and Event.
  @doc false
  def launch(conn, stream_id, decoder) do
    pid =
      case start_link(conn, stream_id) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, {:bond, self()})
    %Stream{id: stream_id, conn: conn, pid: pid, decoder: decoder}
  end

  @doc """
  Creates a stream directly from function call syntax.

  This is equivalent to calling `SpaceEx.Procedure.create/1` and `SpaceEx.Stream.create/2`.

  ## Example

  ```elixir
  stream =
    SpaceEx.SpaceCenter.Flight.mean_altitude(flight)
    |> SpaceEx.Stream.stream()

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
    SpaceEx.SpaceCenter.Flight.mean_altitude(flight)
    |> SpaceEx.Stream.stream_fn()

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
  paused = SpaceEx.SpaceCenter.paused(conn) |> SpaceEx.Stream.stream()

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
    KRPC.set_stream_rate(stream.conn, stream.stream_id, rate || 0)
  end

  @doc """
  Start a previously added stream.

  If a stream is created with `start: false`, you can use this function to
  choose when to start receiving data.
  """

  def start(stream) do
    KRPC.start_stream(stream.conn, stream.stream_id)
  end

  @doc """
  Detach from a stream, and shut it down if possible.

  Streams will not shut down until all processes that depend on this stream
  have exited or have called this function.  This is to prevent streams
  unexpectedly closing for all processes, just because one of them is done.
  """

  def remove(stream) do
    GenServer.call(stream.pid, {:unbond, self()})
  end

  @doc false
  def start_link(conn, stream_id) do
    GenServer.start_link(
      __MODULE__,
      {%State{id: stream_id, conn: conn}, self()},
      name: {:via, StreamConnection.Registry, {conn.stream_pid, stream_id}}
    )
  end

  @doc false
  def init({%State{conn: conn} = state, launching_pid}) do
    # Re-home this process to the StreamConnection itself.
    Process.monitor(conn.stream_pid)
    Process.link(conn.stream_pid)
    Process.unlink(launching_pid)
    {:ok, state}
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

  def handle_call({:bond, pid}, _from, state) do
    Process.monitor(pid)
    new_bonds = MapSet.put(state.bonds, pid)
    {:reply, :ok, %State{state | bonds: new_bonds}}
  end

  def handle_call({:unbond, pid}, _from, state) do
    {:reply, :ok, %State{state | bonds: remove_bond(state.bonds, pid)}}
  end

  def handle_info({:stream_result, id, result}, %State{id: id} = state) do
    if result == state.result do
      {:noreply, state}
    else
      Enum.each(state.waitlist, &GenServer.reply(&1, result))
      {:noreply, %State{state | result: result}}
    end
  end

  def handle_info({:DOWN, _ref, :process, dead_pid, _reason}, state) do
    if dead_pid == state.conn.stream_pid do
      exit(:normal)
    else
      {:noreply, %State{state | bonds: remove_bond(state.bonds, dead_pid)}}
    end
  end

  def handle_info(:shutdown, state) do
    # Final check to make sure we haven't gained new bonds.
    if Enum.any?(state.bonds, &Process.alive?/1) do
      {:noreply, state}
    else
      KRPC.remove_stream(state.conn, state.id)
      exit(:normal)
    end
  end

  defp remove_bond(bonds, pid) do
    new_bonds = MapSet.delete(bonds, pid)
    if Enum.empty?(new_bonds), do: send(self(), :shutdown)
    new_bonds
  end
end
