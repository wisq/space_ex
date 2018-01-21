defmodule SpaceEx.Types.SpecialTest do
  use ExUnit.Case, async: true
  alias SpaceEx.{API, Types, ObjectReference}

  test "class type" do
    type = API.Type.parse(%{"code" => "CLASS", "service" => "SpaceCenter", "name" => "Vessel"})
    conn = :dummy_conn

    ref = %ObjectReference{
      id: <<123>>,
      class: "Vessel",
      conn: :dummy_conn
    }

    assert Types.decode(<<123>>, type, conn) == ref
    assert Types.encode(ref, type) == <<123>>
  end

  test "enumeration type" do
    type =
      API.Type.parse(%{
        "code" => "ENUMERATION",
        "service" => "SpaceCenter",
        "name" => "CameraMode"
      })

    assert Types.encode(:free, type) == <<2>>
    assert Types.encode(:chase, type) == <<4>>
    assert Types.decode(<<6>>, type, nil) == :locked
    assert Types.decode(<<8>>, type, nil) == :orbital
  end

  # These only occur in parameters, never in return values.
  test "procedure call type (encode only)" do
    type = API.Type.parse(%{"code" => "PROCEDURE_CALL"})
    proc = SpaceEx.SpaceCenter.rpc_save(:dummy_conn, "SaveName")

    assert Types.encode(proc, type) ==
             <<10, 11, "SpaceCenter", 18, 4, "Save", 26, 13, 8, 0, 18, 9, 8, "SaveName">>
  end
end
