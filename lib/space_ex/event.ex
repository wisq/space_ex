defmodule SpaceEx.Event do
  use GenServer
  require SpaceEx.Types

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

  # FIXME: should stop the stream after waiting once
  defdelegate wait(stream, timeout \\ :infinity), to: SpaceEx.Stream

  defp decode_event(value), do: SpaceEx.Types.decode(value, :BOOL)
end
