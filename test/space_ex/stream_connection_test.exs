defmodule SpaceEx.StreamConnectionTest do
  use ExUnit.Case, async: true

  import SpaceEx.ConnectionHelper
  # alias SpaceEx.ConnectionHelper.BackgroundConnection

  alias SpaceEx.StreamConnection

  alias SpaceEx.Protobufs.{
    StreamUpdate,
    StreamResult,
    ProcedureResult
  }

  test "stream results are delivered to registered process" do
    state = start_connection() |> accept_rpc() |> accept_stream() |> assert_connected()

    StreamConnection.Registry.register_name({state.conn.stream_pid, 123}, self())
    StreamConnection.Registry.register_name({state.conn.stream_pid, 789}, self())

    result1 = ProcedureResult.new(value: <<4, 5, 6>>)
    result2 = ProcedureResult.new(value: <<10, 11, 12>>)

    StreamUpdate.new(
      results: [
        StreamResult.new(id: 123, result: result1),
        StreamResult.new(id: 789, result: result2)
      ]
    )
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, ^result1}
    assert_receive {:stream_result, 789, ^result2}

    result3 = ProcedureResult.new(value: <<0, 4, 5, 1>>)
    result4 = ProcedureResult.new(value: <<42, 42, 42, 42>>)

    StreamUpdate.new(
      results: [
        StreamResult.new(id: 123, result: result3),
        StreamResult.new(id: 789, result: result4)
      ]
    )
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, ^result3}
    assert_receive {:stream_result, 789, ^result4}
  end

  test "unknown stream IDs are handled gracefully" do
    state = start_connection() |> accept_rpc() |> accept_stream() |> assert_connected()

    StreamConnection.Registry.register_name({state.conn.stream_pid, 123}, self())

    result1 = ProcedureResult.new(value: <<4, 5, 6>>)
    result2 = ProcedureResult.new(value: <<10, 11, 12>>)

    StreamUpdate.new(results: [StreamResult.new(id: 789, result: result2)])
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    refute_receive {:stream_result, _, _}

    StreamUpdate.new(results: [StreamResult.new(id: 123, result: result1)])
    |> StreamUpdate.encode()
    |> send_message(state.stream_socket)

    assert_receive {:stream_result, 123, ^result1}
  end

  @tag :capture_log
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
