defmodule SpaceEx.KRPC do
  use SpaceEx.Gen, exclude: [:add_stream]

  def add_stream!(conn, call, start) do
    args = [
      SpaceEx.Types.encode(call, :PROCEDURE_CALL),
      SpaceEx.Types.encode(start, :BOOL),
    ]

    {:ok, stream_obj_bytes} = SpaceEx.Connection.call_rpc(conn, "KRPC", "AddStream", args)
    stream_obj = SpaceEx.Protobufs.Stream.decode(stream_obj_bytes)
    stream_id = stream_obj.id

    {:ok, pid} = SpaceEx.Stream.start_link(stream_id)
    SpaceEx.StreamConnection.register_stream(conn, stream_id, pid)

    fn -> SpaceEx.Stream.get_value(pid) end
  end
end
