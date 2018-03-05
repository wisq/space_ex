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

  Alternatively, you can use `SpaceEx.ProcedureCall.create/1` to create a reference
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
    |> SpaceEx.ProcedureCall.create()
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
      subscriptions: %{},
      bonds: MapSet.new()
    )
  end

  defmodule Result do
    @moduledoc """
    Raw result from a stream, timestamped, not decoded.

    Normally you won't use or see this structure in your own code.  Most `SpaceEx.Stream` functions will return just the decoded value by default.

    ## Keys

    * `:timestamp` — A `NaiveDateTime` indicating when the result was received.
    * `:value` — The stream result value, in raw bytes, or `nil` if error.
    * `:error` — The stream error value, as text, or `nil` if no error.
    """

    @enforce_keys [:timestamp, :value, :error]
    defstruct(
      timestamp: nil,
      value: nil,
      error: nil
    )
  end

  defmodule Subscription do
    @moduledoc false

    @enforce_keys [:pid, :immediate, :remove]
    defstruct(
      pid: nil,
      immediate: nil,
      remove: nil
    )
  end

  defmodule StaleDataError do
    defexception [:error, :message, :result, :age, :max_age]

    @moduledoc """
    Thrown by `SpaceEx.Stream.receive_next/2` if the received data is too old.

    This prevents code from falling behind if the stream rate is too high, relative to the handler's execution speed.

    ## Fields

    * `:result` — The received `SpaceEx.Stream.Result` structure.
    * `:age` — the age at the time of the `SpaceEx.Stream.receive_next/2` call.
    * `:max_age` — the `:max_age` parameter to `SpaceEx.Stream.receive_next/2`.
    """

    def exception(opts) do
      result = Keyword.fetch!(opts, :result)
      age = Keyword.fetch!(opts, :age)
      max_age = Keyword.fetch!(opts, :max_age)

      %StaleDataError{
        result: result,
        age: age,
        max_age: max_age,
        message:
          "Stale data (age: #{age}ms, max: #{max_age}ms) from stream -- increase handler speed or decrease stream rate"
      }
    end
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

  `procedure` should be a `SpaceEx.ProcedureCall` structure.  The stream's value
  will be the result of calling this procedure over and over (with the same
  arguments each time).

  See the module documentation for usage examples.

  ## Options

  * `:start` — when `false`, the stream is created, but not started.  Default: `start: true`.
  * `:rate` — the stream's update rate, in updates per second.  Default: unlimited.
  """

  def create(procedure, opts \\ []) do
    start = Keyword.get(opts, :start, true)
    rate = Keyword.get(opts, :rate, 0)

    conn = procedure.conn
    stream = KRPC.add_stream(conn, procedure, start: start)

    if rate != 0 do
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

  This is equivalent to calling `SpaceEx.ProcedureCall.create/1` and `SpaceEx.Stream.create/2`.

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
      require SpaceEx.ProcedureCall

      SpaceEx.ProcedureCall.create(unquote(function_call))
      |> SpaceEx.Stream.create(unquote(opts))
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
  Convenience function to return a stream and a `get_fn/1` function.

  When passed a `stream` object, will return `{stream, get_fn(stream)}`.

  ## Example

  ```elixir
  {stream, altitude} =
    SpaceEx.SpaceCenter.Flight.mean_altitude(flight)
    |> SpaceEx.Stream.stream()
    |> SpaceEx.Stream.with_get_fn()

  altitude.() |> IO.inspect  # 76.64177794696297
  ```
  """

  def with_get_fn(%Stream{} = stream), do: {stream, get_fn(stream)}

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
    GenServer.call(stream.pid, :get, timeout)
    |> return_stream_result(stream)
  end

  defp return_stream_result(result, stream) do
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
  Receive the next decoded value from a stream as a message.

  This is the non-blocking version of `wait/2`.  As soon as the stream receives
  a value, a message will be delivered to the calling process.

  Messages will continue to be sent until the calling process calls
  `unsubscribe/1` (unless the `:remove` option is true; see below).

  It's recommended that you use either `receive_latest/2` or `receive_next/2`
  to receive messages from streams.  These functions are designed to prevent
  unexpected results if your code processes stream messages slower than the
  stream generates them.

  If you choose to receive stream results directly instead, the format is
  `{:stream_result, id, result}` where `id` is the value of `stream.id` and
  `result` is a `SpaceEx.Stream.Result` structure.

  ## Options

  * `:immediate` — if `true` and the stream has already received at least one
    result, the latest result will be sent and no subscription will occur.
    Default: `false`
  * `:remove` — if `true`, then `remove/1` (and `unsubscribe/1`) will be called
    immediately after sending the subscribed result.  Only one message will be
    delivered.  Default: `false`
  """
  def subscribe(stream, opts \\ []) do
    sub = %Subscription{
      pid: self(),
      immediate: Keyword.get(opts, :immediate, false),
      remove: Keyword.get(opts, :remove, false)
    }

    case GenServer.call(stream.pid, {:subscribe, sub}) do
      :ok -> :ok
      {:already_subscribed, sub} -> raise "Subscription already exists: #{inspect(sub)}"
    end
  end

  @doc """
  Cancels a previous subscription created by `subscribe/2`.

  The calling process will no longer receive stream result messages for the
  given stream.  Note that there may still be stream results already waiting in
  the process mailbox, but no more will be added once this function returns.
  """
  def unsubscribe(stream) do
    pid = self()

    case GenServer.call(stream.pid, {:unsubscribe, pid}) do
      :ok -> :ok
      :not_subscribed -> raise "Process #{inspect(pid)} is not subscribed to stream"
    end
  end

  @doc """
  Receives the latest value from a subscribed stream using `subscribe/2`.

  If no stream results for `stream` are in the process mailbox, this will block
  (up to `timeout` milliseconds) until a result is received.  Otherwise, it
  will immediately return the latest stream result and discard the rest.

  This is generally the best way to receive results from a subscribed stream,
  since most code is only concerned with the current value of the stream.  If
  your receive loop is sufficiently fast (relative to the stream rate), it can
  process every single value; otherwise, it will skip values in order to stay
  current and not flood the process mailbox.
  """
  def receive_latest(stream, timeout \\ 5000) do
    stream_id = stream.id

    receive do
      {:stream_result, ^stream_id, result} ->
        receive_latest_flush(stream_id, result)
        |> return_stream_result(stream)
    after
      timeout -> raise "No stream result received after #{timeout}ms"
    end
  end

  defp receive_latest_flush(stream_id, last_result) do
    receive do
      {:stream_result, ^stream_id, next_result} -> receive_latest_flush(stream_id, next_result)
    after
      0 -> last_result
    end
  end

  @doc """
  Receives the next value from a subscribed stream using `subscribe/2`.

  If no stream results for `stream` are in the process mailbox, this will block
  (up to `timeout` milliseconds) until a result is received.  Otherwise, it
  will immediately return the first stream result in the process mailbox.

  This can be used if your code must monitor _every_ received stream result,
  e.g. if you're monitoring for a rare abnormal value in the data.  This is a
  relatively rare use case — especially since streams have a polling rate, so
  there's no guarantee you'll be able to catch said value at all.

  In most cases, your code only needs the current value of a stream, and so you
  should use `receive_latest/2` instead.

  ## Loop performance & falling behind

  Since messages are being constantly sent to your process, and `receive_next`
  does not skip messages, your loop needs to be fast enough (relative to the
  stream rate) to process all messages and not fall behind.  Otherwise, the
  process mailbox will continually grow with more and more pending results, and
  the results processed by your code will be more and more out-of-date.

  Falling behind can often be subtle and hard to detect, so `receive_next`
  has a built-in safeguard by default.  The `:max_age` option indicates the
  maximum age (in milliseconds) of a returned result.  If we would return a
  result older than that, a `SpaceEx.Stream.StaleDataError` is raised instead.

  If your code must monitor every value, then a `SpaceEx.Stream.StaleDataError`
  is a fatal error — you should increase the speed of your code or pick a lower
  stream rate.  Otherwise, there are various ways to handle this error.  For
  example, you could process the data anyway (via the `:result` field in the
  error), or you could issue a one-off `receive_latest/2` call to flush all
  pending data and start over from the latest.  However, if you're encountering
  this error regularly, you should probably rethink your approach.

  ## Options

  * `:timeout` — Maximum time (in milliseconds) to wait for the next stream result, or `:infinity` to wait forever.  Default: `5000`
  * `:max_age` — Maximum age of the next stream result, or `:infinity` for no limit.  Default: `1000`
  """
  def receive_next(stream, opts \\ []) do
    stream_id = stream.id
    timeout = Keyword.get(opts, :timeout, 5000)
    max_age = Keyword.get(opts, :max_age, 1000)

    receive do
      {:stream_result, ^stream_id, result} ->
        assert_max_age(result, max_age)
        return_stream_result(result, stream)
    after
      timeout -> raise "No stream result received after #{timeout}ms"
    end
  end

  defp assert_max_age(_result, :infinity), do: :ok

  defp assert_max_age(result, max_age) do
    age = NaiveDateTime.diff(current_timestamp(), result.timestamp, :milliseconds)

    if age > max_age do
      raise StaleDataError, result: result, age: age, max_age: max_age
    end
  end

  @doc """
  Set the update rate of a stream.

  `rate` is the number of updates per second.  Setting the rate to `0` or `nil`
  will remove all rate limiting and update as often as possible.
  """

  def set_rate(%Stream{conn: conn, id: id}, rate) do
    KRPC.set_stream_rate(conn, id, rate || 0)
  end

  @doc """
  Start a previously added stream.

  If a stream is created with `start: false`, you can use this function to
  choose when to start receiving data.
  """

  def start(%Stream{conn: conn, id: id}) do
    KRPC.start_stream(conn, id)
  end

  @doc """
  Detach from a stream, and shut it down if possible.

  Streams will not shut down until all processes that depend on this stream
  have exited or have called this function.  This is to prevent streams
  unexpectedly closing for all processes, just because one of them is done.
  """

  def remove(%Stream{pid: pid}) do
    GenServer.call(pid, {:unbond, self()})
  end

  @doc false
  def start_link(conn, stream_id) do
    state = %State{
      conn: conn,
      id: stream_id
    }

    GenServer.start_link(
      __MODULE__,
      {state, self()},
      name: {:via, StreamConnection.Registry, {conn.stream_pid, stream_id}}
    )
  end

  @doc false
  def init({%State{conn: conn} = state, launching_pid}) do
    # Re-home this process to the StreamConnection itself.
    Process.flag(:trap_exit, true)
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

  def handle_call({:subscribe, sub}, _from, state) do
    cond do
      existing = Map.get(state.subscriptions, sub.pid) ->
        {:reply, {:already_subscribed, existing}, state}

      sub.immediate && !is_nil(state.result) ->
        new_state = dispatch_subscriptions(state, [sub])
        {:reply, :ok, %State{state | bonds: new_state.bonds}}

      true ->
        state = %State{state | subscriptions: Map.put(state.subscriptions, sub.pid, sub)}
        {:reply, :ok, state}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    if Map.has_key?(state.subscriptions, pid) do
      state = %State{state | subscriptions: Map.delete(state.subscriptions, pid)}
      {:reply, :ok, state}
    else
      {:reply, :not_subscribed, state}
    end
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
      state =
        %State{state | result: result}
        |> dispatch_waitlist
        |> dispatch_subscriptions

      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, dead_pid, _reason}, state) do
    {:noreply, %State{state | bonds: remove_bond(state.bonds, dead_pid)}}
  end

  def handle_info({:EXIT, _dead_pid, reason}, _state) do
    # Some linked process -- our StreamConnection, our Connection, and/or its launching process -- has died.
    exit(reason)
  end

  def handle_info(:shutdown, state) do
    # Final check to make sure we haven't gained new bonds.
    if Enum.any?(state.bonds, &Process.alive?/1) do
      {:noreply, state}
    else
      KRPC.cast_remove_stream(state.conn, state.id)
      Process.unlink(state.conn.stream_pid)
      exit(:normal)
    end
  end

  defp remove_bond(bonds, pid) do
    new_bonds = MapSet.delete(bonds, pid)
    if Enum.empty?(new_bonds), do: send(self(), :shutdown)
    new_bonds
  end

  defp dispatch_waitlist(state) do
    Enum.each(state.waitlist, &GenServer.reply(&1, state.result))
    %State{state | waitlist: []}
  end

  defp dispatch_subscriptions(state) do
    if Enum.empty?(state.subscriptions) do
      state
    else
      subs = Map.values(state.subscriptions)
      dispatch_subscriptions(state, subs)
    end
  end

  defp dispatch_subscriptions(state, subs) do
    Enum.each(subs, fn sub ->
      send(sub.pid, {:stream_result, state.id, state.result})
    end)

    remove_sub_pids = Enum.filter(subs, & &1.remove) |> Enum.map(& &1.pid)

    new_bonds =
      remove_sub_pids
      |> Enum.reduce(state.bonds, fn pid, bonds ->
        remove_bond(bonds, pid)
      end)

    new_subs = Map.drop(state.subscriptions, remove_sub_pids)

    %State{state | bonds: new_bonds, subscriptions: new_subs}
  end

  @doc false
  def package_result(result) do
    %Result{
      timestamp: current_timestamp(),
      value: result.value,
      error: result.error
    }
  end

  defp current_timestamp, do: NaiveDateTime.utc_now()
end
