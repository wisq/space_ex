defmodule SpaceEx.TypesTest do
  use ExUnit.Case
  alias SpaceEx.{API, Types, ObjectReference}
  require SpaceEx.Procedure

  test "boolean type" do
    type = API.Type.parse(%{"code" => "BOOL"})
    assert Types.encode(true, type) == <<1>>
    assert Types.encode(false, type) == <<0>>
    assert Types.decode(<<1>>, type, nil) == true
    assert Types.decode(<<0>>, type, nil) == false
  end

  test "string type" do
    type = API.Type.parse(%{"code" => "STRING"})
    assert Types.encode("hello world", type) == <<11, "hello world">>
    assert Types.decode(<<8, "farewell">>, type, nil) == "farewell"
  end

  test "string type with long string" do
    type = API.Type.parse(%{"code" => "STRING"})

    long = String.duplicate("long ", 10_000)
    assert String.length(long) == 50_000

    # 50,000 in base-128 is [3, 6, 80].
    # In reverse order, and with high bit set (+128) for the first two,
    # that's [80+128 = 208, 6+128 = 134, 3].
    assert Types.encode(long, type) == <<208, 134, 3>> <> long
    assert Types.decode(<<208, 134, 3>> <> long, type, nil) == long
  end

  test "float type" do
    type = API.Type.parse(%{"code" => "FLOAT"})
    assert Types.encode(123.456789, type) == <<224, 233, 246, 66>>
    # Yay for awful `float` precision.
    assert Types.decode(<<224, 233, 246, 66>>, type, nil) == 123.456787109375
  end

  test "double type" do
    type = API.Type.parse(%{"code" => "DOUBLE"})
    assert Types.encode(123.456789, type) == <<11, 11, 238, 7, 60, 221, 94, 64>>
    assert Types.decode(<<11, 11, 238, 7, 60, 221, 94, 64>>, type, nil) == 123.456789
  end

  test "tuple type" do
    type =
      API.Type.parse(%{"code" => "TUPLE", "types" => [%{"code" => "BOOL"}, %{"code" => "STRING"}]})

    assert Types.encode({true, "foo"}, type) == <<10, 1, 1, 10, 4, 3, "foo">>
    assert Types.decode(<<10, 1, 0, 10, 7, 6, "foobar">>, type, nil) == {false, "foobar"}
  end

  test "list type" do
    type = API.Type.parse(%{"code" => "LIST", "types" => [%{"code" => "STRING"}]})

    assert Types.encode(["hello", "fair", "world"], type) ==
             <<10, 6, 5, "hello", 10, 5, 4, "fair", 10, 6, 5, "world">>

    assert Types.decode(<<10, 9, 8, "farewell", 10, 6, 5, "cruel", 10, 6, 5, "world">>, type, nil) ==
             ["farewell", "cruel", "world"]
  end

  test "set type" do
    type = API.Type.parse(%{"code" => "SET", "types" => [%{"code" => "STRING"}]})
    set = MapSet.new(["foo", "bar", "baz"])

    # The wire value depends on what order `MapSet` produces its enumeration contents in.
    # I'm pretty sure it just sorts them, but let's do a chunkwise comparison to be safe.
    assert chunks =
             Types.encode(set, type)
             |> :binary.bin_to_list()
             |> Enum.chunk_every(6)
             |> Enum.map(&:binary.list_to_bin/1)

    assert Enum.count(chunks) == 3
    assert <<10, 4, 3, "foo">> in chunks
    assert <<10, 4, 3, "bar">> in chunks
    assert <<10, 4, 3, "baz">> in chunks

    # Literally the same wire value as List decoding.
    assert Types.decode(<<10, 9, 8, "farewell", 10, 6, 5, "cruel", 10, 6, 5, "world">>, type, nil) ==
             MapSet.new(["farewell", "cruel", "world"])
  end

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

  test "procedure call type (encode only)" do
    type = API.Type.parse(%{"code" => "PROCEDURE_CALL"})
    proc = SpaceEx.SpaceCenter.rpc_save(:dummy_conn, "SaveName")

    assert Types.encode(proc, type) ==
             <<10, 11, "SpaceCenter", 18, 4, "Save", 26, 13, 8, 0, 18, 9, 8, "SaveName">>
  end

  test "protobuf type (decode only)" do
    type = API.Type.parse(%{"code" => "STATUS"})

    binary =
      <<10, 5, 48, 46, 52, 46, 51, 16, 139, 3, 24, 255, 5, 37, 11, 255, 0, 30, 45, 0, 216, 212,
        30, 48, 9, 61, 29, 101, 206, 27, 72, 168, 70, 80, 1, 88, 1, 96, 232, 7, 109, 17, 164, 132,
        58, 117, 128, 39, 131, 58, 125, 204, 6, 141, 18, 157, 1, 4, 145, 223, 54>>

    assert %SpaceEx.Protobufs.Status{} = status = Types.decode(binary, type, nil)
    assert status.version == "0.4.3"
    assert status.bytes_written == 767
  end
end
