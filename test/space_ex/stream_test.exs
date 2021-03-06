defmodule SpaceEx.StreamTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  require SpaceEx.Stream
  alias SpaceEx.{Stream, Protobufs, KRPC, SpaceCenter}
  alias Stream.Result

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
    state = MockConnection.start(real_stream: true)

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
    state = MockConnection.start(real_stream: true)

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
    state = MockConnection.start(real_stream: true)

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
    state = MockConnection.start(real_stream: true)

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
    state = MockConnection.start(real_stream: true)

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

  test "remove/1 does not terminate Connection or StreamConnection" do
    state = MockConnection.start(real_stream: true)
    conn = state.conn

    # AddStream response:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(conn)

    # RemoveStream response:
    MockConnection.add_result_value(<<>>, conn)

    stream = KRPC.paused(conn) |> Stream.stream()

    # Monitor all related processes:
    Process.monitor(conn.pid)
    Process.monitor(conn.stream_pid)
    ref = Process.monitor(stream.pid)

    Stream.remove(stream)

    # Stream process should die:
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    # But nobody else should:
    refute_receive {:DOWN, _ref, :process, _pid, :normal}
  end

  test "stream process removes itself and exits if ALL launching processes exit" do
    state = MockConnection.start(real_stream: true)

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

  test "stream(pcall, start: false) and start/1" do
    state = MockConnection.start()

    # KRPC.add_stream response:
    Protobufs.Stream.new(id: 23)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    %Stream{id: 23} = stream = SpaceCenter.ut(state.conn) |> Stream.stream(start: false)

    # KRPC.start response:
    MockConnection.add_result_value(<<>>, state.conn)

    assert :ok = Stream.start(stream)

    assert [add_stream, start_stream] = MockConnection.dump_calls(state.conn)

    assert add_stream.service == "KRPC"
    assert add_stream.procedure == "AddStream"
    # start: false
    assert [_expr_arg, %Argument{value: <<0>>}] = add_stream.arguments

    assert start_stream.service == "KRPC"
    assert start_stream.procedure == "StartStream"
    assert [%Argument{value: <<23>>}] = start_stream.arguments
  end

  test "stream/2 with rate option" do
    state = MockConnection.start()

    # KRPC.add_stream response:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # KRPC.set_stream_rate response:
    MockConnection.add_result_value(<<>>, state.conn)

    %Stream{id: 123} = SpaceCenter.ut(state.conn) |> Stream.stream(rate: 5)

    assert [add_stream, set_rate] = MockConnection.dump_calls(state.conn)

    assert add_stream.service == "KRPC"
    assert add_stream.procedure == "AddStream"
    assert set_rate.service == "KRPC"
    assert set_rate.procedure == "SetStreamRate"

    assert [stream_id_arg, rate_arg] = set_rate.arguments
    assert %Argument{value: <<123>>} = stream_id_arg
    # 5.0 as a float
    assert %Argument{value: <<0, 0, 160, 64>>} = rate_arg
  end

  test "set_rate/2" do
    state = MockConnection.start()

    # Dummy Stream:
    stream = %Stream{id: 23, conn: state.conn, pid: nil, decoder: nil}

    # KRPC.set_stream_rate response:
    MockConnection.add_result_value(<<>>, state.conn)

    assert :ok = Stream.set_rate(stream, 100)

    assert [set_rate] = MockConnection.dump_calls(state.conn)
    assert set_rate.service == "KRPC"
    assert set_rate.procedure == "SetStreamRate"
    assert [stream_id_arg, rate_arg] = set_rate.arguments
    assert %Argument{value: <<23>>} = stream_id_arg
    # 100.0 as a float
    assert %Argument{value: <<0, 0, 200, 66>>} = rate_arg
  end

  test "get_fn/1" do
    state = MockConnection.start(real_stream: true)

    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    stream = KRPC.paused(state.conn) |> Stream.stream()
    get_fn = Stream.get_fn(stream)
    me = self()

    spawn_link(fn ->
      send(me, {:first, get_fn.()})
      send(me, {:second, get_fn.()})
      send(me, {:third, get_fn.()})
    end)

    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # All three will be true, because we're using `get` and not `wait`.
    assert_receive({:first, true})
    assert_receive({:second, true})
    assert_receive({:third, true})
  end

  test "with_get_fn/1" do
    state = MockConnection.start(real_stream: true)

    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    {_stream, get_fn} = KRPC.paused(state.conn) |> Stream.stream() |> Stream.with_get_fn()
    me = self()

    spawn_link(fn ->
      send(me, {:first, get_fn.()})
      send(me, {:second, get_fn.()})
      send(me, {:third, get_fn.()})
    end)

    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # All three will be true, because we're using `get` and not `wait`.
    assert_receive({:first, true})
    assert_receive({:second, true})
    assert_receive({:third, true})
  end

  test "subscribe/1" do
    state = MockConnection.start(real_stream: true)

    # Helper function to send values:
    send_value = fn scene ->
      value = KRPC.GameScene.atom_to_wire(scene)
      result = ProcedureResult.new(value: value)
      send_stream_result(state.stream_socket, 123, result)
    end

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()

    # Send a value before we've subscribed; we won't receive this:
    send_value.(:flight)
    assert Stream.get(stream) == :flight

    # Subscribe to the stream:
    assert :ok = Stream.subscribe(stream)

    # Receive a value now that we're subscribed:
    send_value.(:space_center)
    expected = KRPC.GameScene.atom_to_wire(:space_center)
    assert_receive {:stream_result, 123, %Result{value: ^expected}}
    # We shouldn't have received the first value, only the second:
    not_expected = KRPC.GameScene.atom_to_wire(:flight)
    refute_received {:stream_result, 123, %Result{value: ^not_expected}}

    # Subscriptions are now permanent, so we receive the next value too:
    send_value.(:tracking_station)
    expected = KRPC.GameScene.atom_to_wire(:tracking_station)
    assert_receive {:stream_result, 123, %Result{value: ^expected}}

    # Cancel our subscription:
    assert :ok = Stream.unsubscribe(stream)

    # We should NOT receive the next value:
    send_value.(:editor_sph)
    not_expected = KRPC.GameScene.atom_to_wire(:editor_sph)
    refute_receive {:stream_result, 123, %Result{value: ^not_expected}}
  end

  test "subscribe/1 with name option" do
    state = MockConnection.start(real_stream: true)

    # Helper function to send values:
    send_value = fn id, scene ->
      value = KRPC.GameScene.atom_to_wire(scene)
      result = ProcedureResult.new(value: value)
      send_stream_result(state.stream_socket, id, result)
    end

    # AddStream results:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    Protobufs.Stream.new(id: 456)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream:
    assert %Stream{id: 123} = stream1 = KRPC.current_game_scene(state.conn) |> Stream.stream()
    assert %Stream{id: 456} = stream2 = KRPC.current_game_scene(state.conn) |> Stream.stream()

    # Subscribe to the streams:
    assert :ok = Stream.subscribe(stream1, name: :stream_one)
    assert :ok = Stream.subscribe(stream2, name: :stream_two)

    # Receive values:
    send_value.(123, :space_center)
    send_value.(456, :flight)
    expected1 = KRPC.GameScene.atom_to_wire(:space_center)
    expected2 = KRPC.GameScene.atom_to_wire(:flight)
    assert_receive {:stream_result, :stream_one, %Result{value: ^expected1}}
    assert_receive {:stream_result, :stream_two, %Result{value: ^expected2}}
  end

  test "subscribe/1 does not allow multiple subscriptions with the same pid" do
    state = MockConnection.start()

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()

    # Subscribe to the stream:
    assert :ok = Stream.subscribe(stream)

    # Resubscription should fail:
    err = assert_raise RuntimeError, fn -> Stream.subscribe(stream) end
    assert err.message =~ "Subscription already exists"

    # Subscribing from another PID should be fine:
    me = self()
    spawn_link(fn -> send(me, {:sub, Stream.subscribe(stream)}) end)
    assert_receive {:sub, :ok}
  end

  test "subscribe/1 with immediate: true" do
    state = MockConnection.start(real_stream: true)

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream:
    assert %Stream{id: 123} = stream = KRPC.paused(state.conn) |> Stream.stream()

    # Send a value before we've subscribed:
    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # Ensure the stream has received the result:
    assert Stream.get(stream) == true

    # Subscribe to the stream, with `immediate: true`:
    assert :ok = Stream.subscribe(stream, immediate: true)

    # We should receive the current result immediately.
    assert_receive {:stream_result, 123, %Result{value: <<1>>}}

    # Send another value:
    false_result = ProcedureResult.new(value: <<0>>)
    send_stream_result(state.stream_socket, 123, false_result)

    # We should receive the new value as well.
    assert_receive {:stream_result, 123, %Result{value: <<0>>}}
  end

  test "subscribe/1 with remove: true should exit if no other processes bonded" do
    state = MockConnection.start(real_stream: true)

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream:
    assert %Stream{id: 123} = stream = KRPC.paused(state.conn) |> Stream.stream()
    ref = Process.monitor(stream.pid)

    # Subscribe right away, with `remove: true`:
    assert :ok = Stream.subscribe(stream, remove: true)

    # RemoveStream result:
    MockConnection.add_result_value(<<>>, state.conn)

    # Send a value:
    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # We should receive it, and the stream should shut down:
    assert_receive {:stream_result, 123, %Result{value: <<1>>}}
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}

    # Stream should be removed:
    assert [add, remove] = MockConnection.dump_calls(state.conn)
    assert add.procedure == "AddStream"
    assert remove.procedure == "RemoveStream"
  end

  test "subscribe/1 with remove: true should unsubscribe if other processes bonded" do
    state = MockConnection.start(real_stream: true)

    # AddStream result (twice):
    Enum.each(1..2, fn _ ->
      Protobufs.Stream.new(id: 123)
      |> Protobufs.Stream.encode()
      |> MockConnection.add_result_value(state.conn)
    end)

    # Create the stream:
    assert %Stream{id: 123} = stream = KRPC.paused(state.conn) |> Stream.stream()
    ref = Process.monitor(stream.pid)
    stream_pid = stream.pid

    # Create it again in a second process:
    parent = self()

    child =
      spawn_link(fn ->
        assert %Stream{id: 123, pid: ^stream_pid} = KRPC.paused(state.conn) |> Stream.stream()
        send(parent, :child_started)
        assert_receive :finish
        send(parent, :child_finished)
      end)

    assert_receive(:child_started)

    # Subscribe right away, with `remove: true`:
    assert :ok = Stream.subscribe(stream, remove: true)

    # Send a value:
    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # We should receive it:
    assert_receive {:stream_result, 123, %Result{value: <<1>>}}

    # Send a second value:
    false_result = ProcedureResult.new(value: <<0>>)
    send_stream_result(state.stream_socket, 123, false_result)

    # We should NOT receive anything:
    refute_receive {:stream_result, 123, _}
    # Stream should NOT be down:
    refute_received {:DOWN, ^ref, :process, _pid, :normal}

    # RemoveStream result:
    MockConnection.add_result_value(<<>>, state.conn)

    # Terminate child process:
    send(child, :finish)
    assert_receive(:child_finished)

    # Stream should be terminated:
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}

    # Stream should be removed:
    assert [add, add, remove] = MockConnection.dump_calls(state.conn)
    assert add.procedure == "AddStream"
    assert remove.procedure == "RemoveStream"
  end

  test "subscribe/1 with immediate: true and remove: true should only receive one message (including the immediate message)" do
    state = MockConnection.start(real_stream: true)

    # AddStream result (twice):
    Enum.each(1..2, fn _ ->
      Protobufs.Stream.new(id: 123)
      |> Protobufs.Stream.encode()
      |> MockConnection.add_result_value(state.conn)
    end)

    # RemoveStream result:
    MockConnection.add_result_value(<<>>, state.conn)

    parent = self()

    # Create a stream, which will subscribe *before* first message:
    child_before =
      spawn_link(fn ->
        assert %Stream{id: 123} = stream = KRPC.paused(state.conn) |> Stream.stream()
        Stream.subscribe(stream, immediate: true, remove: true)
        send(parent, {:child_before_started, stream.pid})

        # Should get the first value.
        assert_receive {:stream_result, 123, %Result{value: <<1>>}}
        # Should NOT get the second value.
        refute_receive {:stream_result, 123, %Result{value: <<0>>}}

        send(parent, :child_before_done)
        assert_receive :exit
      end)

    # Create a stream, which will subscribe *after* first message:
    child_after =
      spawn_link(fn ->
        assert %Stream{id: 123} = stream = KRPC.paused(state.conn) |> Stream.stream()
        send(parent, {:child_after_started, stream.pid})

        # Wait for the first value:
        assert Stream.get(stream) == true

        # Subscribe to get the first value as a message:
        Stream.subscribe(stream, immediate: true, remove: true)
        send(parent, :child_after_subscribed)

        # Should get the first value.
        assert_receive {:stream_result, 123, %Result{value: <<1>>}}
        # Should NOT get the second value, since the immediate
        # value counted as our "one and only" value.
        refute_receive {:stream_result, 123, %Result{value: <<0>>}}

        send(parent, :child_after_done)
        assert_receive :exit
      end)

    # Wait for children to start up:
    assert_receive({:child_before_started, stream_pid})
    assert_receive({:child_after_started, ^stream_pid})
    ref = Process.monitor(stream_pid)

    # Send a value:
    true_result = ProcedureResult.new(value: <<1>>)
    send_stream_result(state.stream_socket, 123, true_result)

    # Wait for second child to establish subscription:
    assert_receive :child_after_subscribed

    # Send a second value:
    false_result = ProcedureResult.new(value: <<0>>)
    send_stream_result(state.stream_socket, 123, false_result)

    # Wait for children to finish:
    assert_receive :child_before_done
    assert_receive :child_after_done

    # Stream should be terminated, because both children used remove: true:
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}

    # Stream should be removed:
    assert [add, add, remove] = MockConnection.dump_calls(state.conn)
    assert add.procedure == "AddStream"
    assert remove.procedure == "RemoveStream"

    # Terminate children:
    send(child_before, :exit)
    send(child_after, :exit)
  end

  test "receive_latest/1 should receive and decode latest subscribed value" do
    state = MockConnection.start(real_stream: true)

    # Helper function to send values:
    send_value = fn scene ->
      value = KRPC.GameScene.atom_to_wire(scene)
      result = ProcedureResult.new(value: value)
      send_stream_result(state.stream_socket, 123, result)
    end

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream and subscribe:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()
    assert :ok = Stream.subscribe(stream)

    # Receive a value now that we're subscribed:
    send_value.(:space_center)
    assert Stream.receive_latest(stream) == :space_center

    # Send multiple values:
    send_value.(:flight)
    Process.sleep(10)
    send_value.(:tracking_station)
    Process.sleep(10)
    send_value.(:editor_sph)
    Process.sleep(100)

    # We should see only the most recent:
    assert Stream.receive_latest(stream) == :editor_sph
  end

  test "receive_next/1 should receive and decode next subscribed value" do
    state = MockConnection.start(real_stream: true)

    # Helper function to send values:
    send_value = fn scene ->
      value = KRPC.GameScene.atom_to_wire(scene)
      result = ProcedureResult.new(value: value)
      send_stream_result(state.stream_socket, 123, result)
    end

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream and subscribe:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()
    assert :ok = Stream.subscribe(stream)

    # Receive a value now that we're subscribed:
    send_value.(:space_center)
    assert Stream.receive_next(stream) == :space_center

    # Send multiple values:
    send_value.(:flight)
    Process.sleep(10)
    send_value.(:tracking_station)
    Process.sleep(10)
    send_value.(:editor_sph)
    Process.sleep(100)

    # We should see ALL of them:
    assert Stream.receive_next(stream) == :flight
    assert Stream.receive_next(stream) == :tracking_station
    assert Stream.receive_next(stream) == :editor_sph
  end

  test "receive_next/1 should raise if value is older than max_age" do
    state = MockConnection.start(real_stream: true)

    # Helper function to send values:
    send_value = fn scene ->
      value = KRPC.GameScene.atom_to_wire(scene)
      result = ProcedureResult.new(value: value)
      send_stream_result(state.stream_socket, 123, result)
    end

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream and subscribe:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()
    assert :ok = Stream.subscribe(stream)

    # Send values:
    send_value.(:flight)
    Process.sleep(10)
    send_value.(:tracking_station)
    Process.sleep(50)

    # Too old; we want 10ms or less.
    error =
      assert_raise(Stream.StaleDataError, fn ->
        Stream.receive_next(stream, max_age: 10)
      end)

    assert error.result.value == KRPC.GameScene.atom_to_wire(:flight)
    assert error.age > 10
    assert error.max_age == 10

    # Don't care about max_age.
    assert Stream.receive_next(stream, max_age: :infinity) == :tracking_station
  end

  test "streams do not decode values" do
    state = MockConnection.start(real_stream: true)

    # AddStream result:
    Protobufs.Stream.new(id: 123)
    |> Protobufs.Stream.encode()
    |> MockConnection.add_result_value(state.conn)

    # Create the stream and monitor the PID:
    assert %Stream{id: 123} = stream = KRPC.current_game_scene(state.conn) |> Stream.stream()
    Process.monitor(stream.pid)

    # Send a bogus value:
    result = ProcedureResult.new(value: <<1, 2, 3>>)
    send_stream_result(state.stream_socket, 123, result)

    # Decoding should raise an error:
    err =
      assert_raise(FunctionClauseError, fn ->
        Stream.get(stream)
      end)

    assert err.module == KRPC.GameScene
    assert err.function == :wire_to_atom

    me = self()
    # Wait for the next value:
    spawn_link(fn ->
      send(me, {:result, Stream.wait(stream)})
    end)

    # Send a real value:
    value = KRPC.GameScene.atom_to_wire(:flight)
    true_result = ProcedureResult.new(value: value)
    send_stream_result(state.stream_socket, 123, true_result)

    # Should be able to get it, no problem:
    assert_receive {:result, :flight}
  end

  defp send_stream_result(socket, id, result) do
    StreamUpdate.new(results: [StreamResult.new(id: id, result: result)])
    |> StreamUpdate.encode()
    |> send_message(socket)
  end
end
