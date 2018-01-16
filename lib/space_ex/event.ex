defmodule SpaceEx.Event do
  use GenServer
  require SpaceEx.Types

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

  * `:rate` — how often the server checks the condition, per second.  Default: unlimited.
  """

  def create(conn, expression, opts \\ []) do
    {:ok, event} = SpaceEx.KRPC.add_event(conn, expression)
    stream_id = event.stream.id

    if rate = opts[:rate] do
      SpaceEx.KRPC.set_stream_rate(conn, stream_id, rate)
    end

    stream = SpaceEx.Stream.launch(conn, stream_id, &decode_event/1)
    SpaceEx.KRPC.start_stream(conn, stream_id)
    stream
  end

  @doc """
  Waits for an event to trigger (become true).

  This will wait until the server reports that the conditional expression has
  become true.  It will block for up to `timeout` milliseconds (default:
  forever, aka `:infinity`), after which it will throw an `exit` signal.

  You can technically catch this exit signal with `try ... catch :exit, _`,
  but it's not generally considered good practice to do so.  As such, `wait/2`
  timeouts should generally be reserved for "something has gone badly wrong".

  If this function is called and returns true (i.e. does not time out), then
  the event is complete.  All future calls will immediately return `true` as
  well, even if the condition is no longer true.
  """

  def wait(event, timeout \\ :infinity) do
    # Don't use Stream.wait here, because it may have already received the
    # "true" value if the condition was true immediately.  The only thing we
    # care about is that the stream has received its first value.
    SpaceEx.Stream.get(event, timeout)
    # TODO: Unregister stream from server and StreamConnection?
    # But maybe keep stream pid alive so this continues to return true immediately.
  end

  defp decode_event(value), do: SpaceEx.Types.decode(value, :BOOL)
end
