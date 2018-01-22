defmodule SpaceEx.StreamTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  require SpaceEx.Stream
  alias SpaceEx.{Stream, Protobufs, KRPC}

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureCall,
    ProcedureResult,
    Argument
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

  test "stream process exits if connection is closed" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 456)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    stream = KRPC.paused(state.conn) |> Stream.stream()
    assert Process.alive?(stream.pid)

    ref = Process.monitor(stream.pid)
    MockConnection.close(state.conn)
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}
  end

  test "stream process exits if server closes stream socket" do
    state = MockConnection.start()

    Protobufs.Stream.new(id: 456)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    stream = KRPC.paused(state.conn) |> Stream.stream()
    assert Process.alive?(stream.pid)

    ref = Process.monitor(stream.pid)
    :ok = :gen_tcp.close(state.stream_socket)
    assert_receive {:DOWN, ^ref, :process, _pid, reason}
    assert reason == "SpaceEx.StreamConnection socket has closed"
  end

  test "stream process removes itself and exits if ALL launching processes call `remove/1`" do
    state = MockConnection.start()

    me = self()

    pids =
      Enum.map(1..3, fn index ->
        Protobufs.Stream.new(id: 123)
        |> Protobufs.Stream.encode()
        |> MockConnection.add_result_value(state.conn)

        spawn_link(fn ->
          stream = KRPC.paused(state.conn) |> Stream.stream()
          send(me, {:stream, index, stream})

          assert_receive :remove, 1000
          Stream.remove(stream)
          assert_receive :exit, 1000
        end)
      end)

    assert_receive {:stream, 1, %Stream{pid: stream_pid}}
    assert_receive {:stream, 2, %Stream{pid: ^stream_pid}}
    assert_receive {:stream, 3, %Stream{pid: ^stream_pid}}

    assert [add, add, add] = MockConnection.dump_calls(state.conn)
    MockConnection.add_result_value("", state.conn)
    ref = Process.monitor(stream_pid)

    [pid1, pid2, pid3] = Enum.shuffle(pids)

    send(pid1, :remove)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    send(pid2, :remove)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    send(pid3, :remove)
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, reason}
    assert reason == :normal

    assert [remove] = MockConnection.dump_calls(state.conn)
    assert remove.service == "KRPC"
    assert remove.procedure == "RemoveStream"
    assert [%Argument{value: <<123>>}] = remove.arguments

    Enum.each(pids, &send(&1, :exit))
  end

  test "stream process removes itself and exits if ALL launching processes exit" do
    state = MockConnection.start()

    me = self()

    pids =
      Enum.map(1..3, fn index ->
        Protobufs.Stream.new(id: 42)
        |> Protobufs.Stream.encode()
        |> MockConnection.add_result_value(state.conn)

        spawn_link(fn ->
          stream = KRPC.paused(state.conn) |> Stream.stream()
          send(me, {:stream, index, stream})

          assert_receive :exit, 1000
        end)
      end)
      |> Enum.shuffle()

    assert_receive {:stream, 1, %Stream{pid: stream_pid}}
    assert_receive {:stream, 2, %Stream{pid: ^stream_pid}}
    assert_receive {:stream, 3, %Stream{pid: ^stream_pid}}

    assert [add, add, add] = MockConnection.dump_calls(state.conn)
    MockConnection.add_result_value("", state.conn)
    ref = Process.monitor(stream_pid)

    [pid1, pid2, pid3] = Enum.shuffle(pids)

    send(pid1, :exit)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    send(pid2, :exit)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    send(pid3, :exit)
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, reason}
    assert reason == :normal

    assert [remove] = MockConnection.dump_calls(state.conn)
    assert remove.service == "KRPC"
    assert remove.procedure == "RemoveStream"
    assert [%Argument{value: <<42>>}] = remove.arguments
  end

  defp send_stream_result(socket, id, result) do
    StreamUpdate.new(results: [StreamResult.new(id: id, result: result)])
    |> StreamUpdate.encode()
    |> send_message(socket)
  end
end
