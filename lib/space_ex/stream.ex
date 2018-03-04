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

    @enforce_keys [:id, :conn, :decoder]
    defstruct(
      id: nil,
      conn: nil,
      result: nil,
      decoder: nil,
      waitlist: [],
      subscriptions: %{},
      bonds: MapSet.new()
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
      case start_link(conn, stream_id, decoder) do
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
  Receive the next decoded value from a stream as a message.

  This is the non-blocking version of `wait/2`.  As soon as the stream receives
  a value, a message will be delivered to the calling process.

  Messages will continue to be sent until the calling process calls
  `unsubscribe/1` (unless the `:remove` option is true; see below).

  It's recommended that you use either `receive_latest/3` or `receive_next/3`
  to receive messages from streams.  These functions are designed to prevent
  unexpected results if your code processes stream messages slower than the
  stream generates them.

  If you choose to receive stream results directly instead, the format is
  `{:stream_result, id, value}` where `id` is the value of `stream.id`.

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
  def start_link(conn, stream_id, decoder) do
    state = %State{
      conn: conn,
      id: stream_id,
      decoder: decoder
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

  # I was tempted to put this in a subprocess, but casual benchmarking suggests
  # that the time to create a subprocess (even from the parent's detached POV)
  # is greater than the time to just decode a typical simple value.
  #
  # Besides, we're not decoding every value.  If this takes a while, and
  # several results back up in our queue, then we'll (by definition) process
  # those results before we get the user's next `subscribe` request.  Those
  # results will go undecoded, clearing our queue.
  defp dispatch_subscriptions(state, subs) do
    value = state.decoder.(state.result.value)

    Enum.each(subs, fn sub ->
      send(sub.pid, {:stream_result, state.id, value})
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
end
