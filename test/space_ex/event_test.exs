defmodule SpaceEx.EventTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  require SpaceEx.Procedure
  alias SpaceEx.{Event, Stream, Procedure, Protobufs, KRPC, KRPC.Expression, Types, API}

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureResult,
    Argument
  }

  alias SpaceEx.Test.MockConnection
  import SpaceEx.Test.ConnectionHelper, only: [send_message: 2]

  test "create/2 calls KRPC.add_event with encoded Expression" do
    state = MockConnection.start()
    conn = state.conn

    # To create an expression, the only reply we need is a server-side ID.
    MockConnection.add_result_value(<<86>>, conn)

    # Prepare the simplest possible boolean expression.
    # (Yes, this really works.  It's boolean, after all.)
    paused_call = KRPC.paused(conn) |> Procedure.create()
    expr = Expression.call(conn, paused_call)
    assert expr.id == <<86>>

    # Prepare two replies:
    # ... the server's AddEvent reply ...
    Protobufs.Event.new(stream: Protobufs.Stream.new(id: 99))
    |> Protobufs.Event.encode()
    |> MockConnection.add_result_value(conn)

    # ... and a StartStream reply, empty.
    MockConnection.add_result_value("", conn)

    # Create the event (which is really just a stream.)
    assert %Stream{id: 99} = Event.create(conn, expr)

    # Now check the requests we got.
    # (Expressions will be tested in their own test module.)
    assert [_create_expr, add_event, start_stream] = MockConnection.dump_calls(conn)

    # KRPC.add_event with expression ID (86).
    assert add_event.service == "KRPC"
    assert add_event.procedure == "AddEvent"
    assert [%Argument{value: <<86>>}] = add_event.arguments

    # KRPC.start_stream with stream ID (99).
    assert start_stream.service == "KRPC"
    assert start_stream.procedure == "StartStream"
    assert [%Argument{value: <<99>>}] = start_stream.arguments
  end

  test "wait/1 blocks until event stream receives FIRST result" do
    state = MockConnection.start()
    conn = state.conn

    # Create a dummy Expression reference.
    type = %API.Type.Class{name: "Expression"}
    expr = Types.decode(<<42>>, type, conn)

    # Prepare the AddEvent and StartStream replies.
    Protobufs.Event.new(stream: Protobufs.Stream.new(id: 66))
    |> Protobufs.Event.encode()
    |> MockConnection.add_result_value(conn)

    MockConnection.add_result_value("", conn)

    # Create the Event/Stream.
    assert %Stream{id: 66} = event = Event.create(conn, expr)
    assert [_add_event, _start_stream] = MockConnection.dump_calls(conn)

    me = self()
    # Now, we wait.
    spawn_link(fn ->
      send(me, {:first, Event.wait(event, 100)})
      send(me, {:second, Event.wait(event, 100)})
      send(me, {:third, Event.wait(event, 100)})
    end)

    # Send the result down the wire.
    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 66, true_result)

    # All three should arrive immediately, since Event.wait == Stream.get.
    assert_receive({:first, true})
    assert_receive({:second, true})
    assert_receive({:third, true})
  end

  # It may seem redundant to test Event lifecycles, since they're just Streams, but
  # it's important to make sure that `Event.create/2` triggers the same bonding logic
  # as `Stream.create/2` et al.
  test "event stream process removes itself and exits if ALL launching processes call `remove/1`" do
    state = MockConnection.start()
    conn = state.conn

    # Create a dummy Expression reference.
    type = %API.Type.Class{name: "Expression"}
    expr = Types.decode(<<42>>, type, conn)

    me = self()

    # We'll launch three Events (Streams) in separate processes
    # and then individually trigger removes in each.
    {pids, stream_pids} =
      Enum.map(1..3, fn index ->
        # Prepare the AddEvent and StartStream replies.
        Protobufs.Event.new(stream: Protobufs.Stream.new(id: 66))
        |> Protobufs.Event.encode()
        |> MockConnection.add_result_value(conn)

        MockConnection.add_result_value("", conn)

        pid =
          spawn_link(fn ->
            assert %Stream{id: 66} = event = Event.create(conn, expr)
            send(me, {:stream, index, event})

            assert_receive :remove, 1000
            Event.remove(event)
            assert_receive :exit, 1000
          end)

        # Keep this inside the loop, so we don't have race conditions
        # with regards to the ordering of [AddEvent, StartStream] responses.
        assert_receive {:stream, ^index, %Stream{pid: stream_pid}}
        {pid, stream_pid}
      end)
      |> Enum.unzip()

    # We should three of the same stream_pid.
    assert [stream_pid, stream_pid, stream_pid] = stream_pids
    # And three pairs of [add, start] requests.
    assert [add, start, add, start, add, start] = MockConnection.dump_calls(state.conn)

    # Prepare the RemoveStream response and monitor the stream PID.
    MockConnection.add_result_value("", state.conn)
    ref = Process.monitor(stream_pid)

    # Remove them in a random order, to avoid any ordering favouratism.
    [pid1, pid2, pid3] = Enum.shuffle(pids)

    # First remove does nothing.
    send(pid1, :remove)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    # Second remove does nothing.
    send(pid2, :remove)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    # Third remove is the trigger.
    send(pid3, :remove)
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, reason}
    assert reason == :normal

    # Check the RemoveStream request.
    assert [remove] = MockConnection.dump_calls(state.conn)
    assert remove.service == "KRPC"
    assert remove.procedure == "RemoveStream"
    assert [%Argument{value: <<66>>}] = remove.arguments

    Enum.each(pids, &send(&1, :exit))
  end

  test "event stream process removes itself and exits if ALL launching processes exit" do
    state = MockConnection.start()
    conn = state.conn

    # Create a dummy Expression reference.
    type = %API.Type.Class{name: "Expression"}
    expr = Types.decode(<<42>>, type, conn)

    me = self()

    # We'll launch three Events (Streams) in separate processes
    # and then individually trigger exits in each.
    {pids, stream_pids} =
      Enum.map(1..3, fn index ->
        # Prepare the AddEvent and StartStream replies.
        Protobufs.Event.new(stream: Protobufs.Stream.new(id: 66))
        |> Protobufs.Event.encode()
        |> MockConnection.add_result_value(conn)

        MockConnection.add_result_value("", conn)

        pid =
          spawn_link(fn ->
            assert %Stream{id: 66} = event = Event.create(conn, expr)
            send(me, {:stream, index, event})

            assert_receive :exit, 1000
          end)

        # Keep this inside the loop, so we don't have race conditions
        # with regards to the ordering of [AddEvent, StartStream] responses.
        assert_receive {:stream, ^index, %Stream{pid: stream_pid}}
        {pid, stream_pid}
      end)
      |> Enum.unzip()

    # We should three of the same stream_pid.
    assert [stream_pid, stream_pid, stream_pid] = stream_pids
    # And three pairs of [add, start] requests.
    assert [add, start, add, start, add, start] = MockConnection.dump_calls(state.conn)

    # Prepare the RemoveStream response and monitor the stream PID.
    MockConnection.add_result_value("", state.conn)
    ref = Process.monitor(stream_pid)

    # Exit in a random order, to avoid any ordering favouratism.
    [pid1, pid2, pid3] = Enum.shuffle(pids)

    # First exit does nothing.
    send(pid1, :exit)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    # Second exit does nothing.
    send(pid2, :exit)
    refute_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}
    assert [] = MockConnection.dump_calls(state.conn)

    # Third exit is the last needed.
    send(pid3, :exit)
    assert_receive {:DOWN, ^ref, :process, ^stream_pid, reason}
    assert reason == :normal

    # Check RemoveStream request.
    assert [remove] = MockConnection.dump_calls(state.conn)
    assert remove.service == "KRPC"
    assert remove.procedure == "RemoveStream"
    assert [%Argument{value: <<66>>}] = remove.arguments
  end

  defp send_stream_result(socket, id, result) do
    StreamUpdate.new(results: [StreamResult.new(id: id, result: result)])
    |> StreamUpdate.encode()
    |> send_message(socket)
  end
end