defmodule SpaceEx.Service.KRPCTest do
  use ExUnit.Case, async: true

  alias SpaceEx.Test.MockConnection

  alias SpaceEx.KRPC
  alias SpaceEx.Protobufs.Argument

  setup do
    {:ok, MockConnection.start()}
  end

  # Tests:
  #   * no arguments
  #   * simple return value
  test "KRPC.paused/1", state do
    MockConnection.add_result_value(<<1>>, state.conn)
    assert KRPC.paused(state.conn) == true

    MockConnection.add_result_value(<<0>>, state.conn)
    assert KRPC.paused(state.conn) == false

    assert [call, call] = MockConnection.dump_calls(state.conn)
    assert call.service == "KRPC"
    assert call.procedure == "get_Paused"
    assert call.arguments == []
  end

  # Tests:
  #   * simple argument
  #   * no return value
  test "KRPC.set_paused/2", state do
    MockConnection.add_result_value(<<>>, state.conn)
    assert KRPC.set_paused(state.conn, true) == :ok

    assert [call1] = MockConnection.dump_calls(state.conn)
    assert call1.service == "KRPC"
    assert call1.procedure == "set_Paused"
    assert [%Argument{position: 0, value: <<1>>}] = call1.arguments

    MockConnection.add_result_value(<<>>, state.conn)
    assert KRPC.set_paused(state.conn, false) == :ok

    assert [call2] = MockConnection.dump_calls(state.conn)
    assert call2.service == "KRPC"
    assert call2.procedure == "set_Paused"
    assert [%Argument{position: 0, value: <<0>>}] = call2.arguments
  end

  # Tests:
  #   * enumeration return value
  test "KRPC.current_game_scene/1", state do
    MockConnection.add_result_value(<<2>>, state.conn)
    assert KRPC.current_game_scene(state.conn) == :flight

    MockConnection.add_result_value(<<4>>, state.conn)
    assert KRPC.current_game_scene(state.conn) == :tracking_station

    assert [call, call] = MockConnection.dump_calls(state.conn)
    assert call.service == "KRPC"
    assert call.procedure == "get_CurrentGameScene"
    assert call.arguments == []
  end
end
