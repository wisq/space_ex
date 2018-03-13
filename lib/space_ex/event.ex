defmodule SpaceEx.Event do
  alias SpaceEx.{API, Types, Stream, KRPC, ObjectReference, Protobufs}

  @bool_type API.Type.parse(%{"code" => "BOOL"})

  @moduledoc """
  Allows for the server to notify us only when a conditional expression becomes true.

  Events are an efficient way to wait for a particular condition or state.
  This could be e.g. waiting for a vessel to reach a given altitude, waiting
  for a certain time, waiting for a burn to be nearly complete, etc.

  To set up an event, you will need to create a `SpaceEx.KRPC.Expression` that
  returns a boolean value.  Generally, this is done by issuing one or more
  "call" expressions (to retrieve useful data), and comparing them with one or
  more "constant" expressions, using comparison expressions like "equals",
  "greater than", etc.  Complex logic chains may be created with boolean
  expressions like "and", "or", etc.

  Events are really just streams that receive their first (and only) update
  once the condition becomes true.  As such, they cannot currently be reused;
  once an event becomes true, subsequent attempts to wait on the same event
  will always return immediately, even if the conditional expression is no
  longer true.
  """

  @doc """
  Creates an event from an expression.

  `expression` should be a `SpaceEx.KRPC.Expression` reference.  The expression
  must return a boolean type.

  ## Options

  * `:start` — whether the event stream should be started immediately.  If `false`, you can prepare an event before it becomes needed later.  Default: `true`
  * `:rate` — how often the server checks the condition, per second.  Default: `0` (unlimited.
  """

  def create(%ObjectReference{} = expression, opts \\ []) do
    start = Keyword.get(opts, :start, true)
    rate = Keyword.get(opts, :rate, 0)

    conn = expression.conn
    %Protobufs.Event{stream: %Protobufs.Stream{id: stream_id}} = KRPC.add_event(conn, expression)

    stream = Stream.launch(conn, stream_id, &decode_event/1)

    if rate != 0 do
      KRPC.set_stream_rate(conn, stream_id, rate)
    end

    if start do
      KRPC.start_stream(conn, stream_id)
    end

    stream
  end

  @doc """
  Waits for an event to trigger (become true).

  This will wait until the server reports that the conditional expression has
  become true.  It will block for up to `opts[:timeout]` milliseconds (default:
  forever, aka `:infinity`), after which it will throw an `exit` signal.

  You can technically catch this exit signal with `try ... catch :exit, _`,
  but it's not generally considered good practice to do so.  As such, `wait/2`
  timeouts should generally be reserved for "something has gone badly wrong".

  If this function is called and returns (i.e. does not time out), then the
  event is complete.  As long as the stream remains alive, future calls will
  immediately return `true` as well, even if the condition is no longer true.

  Since events are single-use, by default, this will call `Event.remove/1`
  before returning.  This will allow the underlying stream to unregister itself
  from the server.  You may suppress this behaviour with the `remove: true` option.
  """
  def wait(event, opts \\ []) do
    remove = Keyword.get(opts, :remove, true)
    timeout = Keyword.get(opts, :timeout, :infinity)

    # Don't use Stream.wait here, because it may have already received the
    # "true" value if the condition was true immediately.  The only thing we
    # care about is that the stream has received its first value.
    value = Stream.get(event, timeout)
    if remove, do: remove(event)
    value
  end

  @doc """
  Start a previously created event.

  See `SpaceEx.Stream.start/1`.
  """
  defdelegate start(event), to: SpaceEx.Stream

  @doc """
  Set the polling rate of an event.

  See `SpaceEx.Stream.set_rate/2`.
  """
  defdelegate set_rate(event, rate), to: SpaceEx.Stream

  @doc """
  Detach from an event, and shut down the underlying stream if possible.

  See `SpaceEx.Stream.remove/1`.
  """
  defdelegate remove(event), to: SpaceEx.Stream

  @doc """
  Receive a message when an event triggers (becomes true).

  This is the non-blocking version of `wait/2`.  Once the event is complete, a
  message will be delivered to the calling process.  By default, this will also
  call `Event.remove/1` to clean up the event stream.

  Because events are effectively just streams, this message will be in the form
  of `{:stream_result, id, result}` where `id` is the value of `event.id` (or
  the `:name` option, if specified).  You can use `Stream.decode/2` to decode
  `result`, or you can just check that `result.value == <<1>>` (`true` in wire
  format) which is almost always the case for event streams.

  This function behaves identically to `SpaceEx.Stream.subscribe/2`, except
  that the `:immediate` and `:remove` options are both `true` by default.  It's
  unlikely that you'll want to change either of these, since event streams only
  ever get a single message.
  """
  def subscribe(event, opts \\ []) do
    opts = opts |> Keyword.put_new(:immediate, true) |> Keyword.put_new(:remove, true)
    Stream.subscribe(event, opts)
  end

  defp decode_event(value), do: Types.decode(value, @bool_type, nil)
end
