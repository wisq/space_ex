defmodule SpaceEx.StreamTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  require SpaceEx.Stream
  alias SpaceEx.{Stream, Protobufs, KRPC}

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureCall,
    ProcedureResult
  }

  alias SpaceEx.Test.MockConnection
  import SpaceEx.Test.ConnectionHelper, only: [send_message: 2]

  test "stream/1 calls KRPC.add_stream with encoded ProcedureCall" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    KRPC.paused(state.conn) |> Stream.stream()

    assert [call] = MockConnection.dump_calls(state.conn)
    assert call.service == "KRPC"
    assert call.procedure == "AddStream"
    assert [arg1, arg2] = call.arguments

    # procedure call argument
    assert proc = ProcedureCall.decode(arg1.value)
    assert proc.service == "KRPC"
    assert proc.procedure == "get_Paused"
    assert proc.arguments == []

    # start: true
    assert arg2.value == <<1>>
  end

  test "stream/1 creates new Stream process that receives stream updates" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 456)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    stream = KRPC.paused(state.conn) |> Stream.stream()

    me = self()

    spawn_link(fn ->
      send(me, {:first, Stream.get(stream, 100)})
      send(me, {:second, Stream.wait(stream, 100)})
      send(me, {:third, Stream.wait(stream, 100)})
    end)

    true_result = ProcedureResult.new(value: <<1>>)
    false_result = ProcedureResult.new(value: <<0>>)

    send_stream_result(state.stream_socket, 456, true_result)
    assert_receive({:first, true})
    send_stream_result(state.stream_socket, 456, false_result)
    assert_receive({:second, false})
    send_stream_result(state.stream_socket, 456, true_result)
    assert_receive({:third, true})
  end

  defp send_stream_result(socket, id, result) do
    StreamUpdate.new(results: [StreamResult.new(id: id, result: result)])
    |> StreamUpdate.encode()
    |> send_message(socket)
  end
end
