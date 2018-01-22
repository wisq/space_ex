defmodule SpaceEx.ConnectionTest do
  use ExUnit.Case, async: true

  import SpaceEx.ConnectionHelper
  alias SpaceEx.ConnectionHelper.BackgroundConnection

  alias SpaceEx.Connection

  alias SpaceEx.Protobufs.{
    Request,
    Response,
    ProcedureResult
  }

  setup do
    {:ok, setup_connection()}
  end

  test "connect!/1", state do
    assert %Connection{} = state.conn
  end

  test "call_rpc/4", state do
    BackgroundConnection.call_rpc(state.bg_conn, "SomeService", "SomeProcedure", ["arg1", "arg2"])

    assert request = assert_receive_message(state.rpc_socket) |> Request.decode()
    assert [call] = request.calls

    assert call.service == "SomeService"
    assert call.procedure == "SomeProcedure"
    assert [arg1, arg2] = call.arguments

    assert arg1.position == 0
    assert arg2.position == 1
    assert arg1.value == "arg1"
    assert arg2.value == "arg2"

    result = ProcedureResult.new(value: "some value")
    response = Response.new(results: [result]) |> Response.encode()

    send_message(response, state.rpc_socket)

    assert_receive {:called, {:ok, "some value"}}
  end

  test "call_rpc/4 allows multiple concurrent pipelined requests", state do
    # Don't try to lump all the calls together without `assert_receive_message`,
    # or else you'll just get a single TCP packet with all three combined.
    Enum.each(1..3, fn _ ->
      BackgroundConnection.call_rpc(state.bg_conn, "service", "provider", [])
      assert_receive_message(state.rpc_socket)
    end)

    Enum.each([10, 20, 30], fn n ->
      result = ProcedureResult.new(value: <<n + 1, n + 2, n + 3>>)

      Response.new(results: [result])
      |> Response.encode()
      |> send_message(state.rpc_socket)
    end)

    assert_receive {:called, {:ok, <<11, 12, 13>>}}
    assert_receive {:called, {:ok, <<21, 22, 23>>}}
    assert_receive {:called, {:ok, <<31, 32, 33>>}}
  end
end
