defmodule SpaceEx.StreamConnectionTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias SpaceEx.StreamConnection

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureResult
  }

  import SpaceEx.Test.ConnectionHelper

  test "stream results are delivered to registered process" do
    state = start_connection() |> accept_rpc() |> accept_stream() |> assert_connected()

    StreamConnection.Registry.register_name({state.conn.stream_pid, 123}, self())
    StreamConnection.Registry.register_name({state.conn.stream_pid, 789}, self())

    pres1 = ProcedureResult.new(value: <<4, 5, 6>>)
    pres2 = ProcedureResult.new(value: <<10, 11, 12>>)

    StreamUpdate.new(
      results: [
        StreamResult.new(id: 123, result: pres1),
        StreamResult.new(id: 789, result: pres2)
      ]
    )
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, result1}
    assert_receive {:stream_result, 789, result2}
    assert result1.value == pres1.value
    assert result2.value == pres2.value

    pres3 = ProcedureResult.new(value: <<0, 4, 5, 1>>)
    pres4 = ProcedureResult.new(value: <<42, 42, 42, 42>>)

    StreamUpdate.new(
      results: [
        StreamResult.new(id: 123, result: pres3),
        StreamResult.new(id: 789, result: pres4)
      ]
    )
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, result3}
    assert_receive {:stream_result, 789, result4}
    assert result3.value == pres3.value
    assert result4.value == pres4.value

    now = NaiveDateTime.utc_now()
    assert NaiveDateTime.diff(result1.timestamp, now, :milliseconds) < 200
    assert NaiveDateTime.diff(result2.timestamp, now, :milliseconds) < 200
    assert NaiveDateTime.diff(result3.timestamp, now, :milliseconds) < 200
    assert NaiveDateTime.diff(result4.timestamp, now, :milliseconds) < 200
  end

  test "unknown stream IDs are handled gracefully" do
    state = start_connection() |> accept_rpc() |> accept_stream() |> assert_connected()

    StreamConnection.Registry.register_name({state.conn.stream_pid, 123}, self())

    pres1 = ProcedureResult.new(value: <<4, 5, 6>>)
    pres2 = ProcedureResult.new(value: <<10, 11, 12>>)

    StreamUpdate.new(results: [StreamResult.new(id: 789, result: pres2)])
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    refute_receive {:stream_result, _, _}

    StreamUpdate.new(results: [StreamResult.new(id: 123, result: pres1)])
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, result1}
    assert result1.value == pres1.value
  end

  test "connection closes if server closes stream socket" do
    state = start_connection() |> accept_rpc() |> accept_stream() |> assert_connected()

    conn_pid = state.conn.pid
    stream_pid = state.conn.stream_pid
    conn_ref = Process.monitor(conn_pid)
    stream_ref = Process.monitor(stream_pid)

    :ok = :gen_tcp.close(state.stream_socket)

    assert_receive {:DOWN, ^conn_ref, :process, ^conn_pid,
                    "SpaceEx.StreamConnection socket has closed"}

    assert_receive {:DOWN, ^stream_ref, :process, ^stream_pid,
                    "SpaceEx.StreamConnection socket has closed"}

    rpc_socket = state.rpc_socket
    assert_receive {:tcp_closed, ^rpc_socket}
  end
end
