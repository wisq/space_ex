defmodule SpaceEx.TypesTest do
  use ExUnit.Case, async: true
  alias SpaceEx.{API, Types, ObjectReference}
  require SpaceEx.Procedure

  test "boolean type" do
    type = API.Type.parse(%{"code" => "BOOL"})
    assert Types.encode(true, type) == <<1>>
    assert Types.encode(false, type) == <<0>>
    assert Types.decode(<<1>>, type, nil) == true
    assert Types.decode(<<0>>, type, nil) == false
  end

  test "bytes type" do
    type = API.Type.parse(%{"code" => "BYTES"})
    assert Types.encode(<<1, 2, 3>>, type) == <<3, 1, 2, 3>>
    assert Types.decode(<<21, "strings are bytes too">>, type, nil) == "strings are bytes too"
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

  test "sint32 type" do
    type = API.Type.parse(%{"code" => "SINT32"})
    # Positive = double it (2468), then base128 (36+19) with raised bits (164+19).
    assert Types.encode(1234, type) == <<164, 19>>
    assert Types.decode(<<164, 19>>, type, nil) == 1234
    # Negative is the same minus one, due to zigzag encoding.
    assert Types.encode(-1234, type) == <<163, 19>>
    assert Types.decode(<<163, 19>>, type, nil) == -1234
  end

  test "uint32 type" do
    type = API.Type.parse(%{"code" => "UINT32"})
    # Base128 (82+9) with raised bits (210+9).
    assert Types.encode(1234, type) == <<210, 9>>
    assert Types.decode(<<210, 9>>, type, nil) == 1234

    # Can encode greater than 32 bits (because :gpb doesn't enforce bit size),
    # but attempting to decode larger than 32 bits will give a 32-bit answer.
    # That's out of spec, though, so I'm not testing it here.  For reference:
    #
    # Types.encode(1_234_567_890_123, type) == <<203, 137, 236, 143, 247, 35>>
    #   (same as below)
    # Types.decode(<<203, 137, 236, 143, 247, 35>>, type, nil) == 1_912_276_171
    #   (1_234_567_890_123 modulo 2^32)
  end

  test "uint64 type" do
    type = API.Type.parse(%{"code" => "UINT64"})
    # Base128 (82+9) with raised bits (210+9).
    assert Types.encode(1234, type) == <<210, 9>>
    assert Types.decode(<<210, 9>>, type, nil) == 1234
    # Can handle numbers larger than 32 bits (4 billion).
    assert Types.encode(1_234_567_890_123, type) == <<203, 137, 236, 143, 247, 35>>
    assert Types.decode(<<203, 137, 236, 143, 247, 35>>, type, nil) == 1_234_567_890_123
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

  test "dictionary type decoding with nested classes" do
    type =
      API.Type.parse(%{
        "code" => "DICTIONARY",
        "types" => [
          %{"code" => "STRING"},
          %{"code" => "CLASS", "service" => "SpaceCenter", "name" => "CelestialBody"}
        ]
      })

    # Wire-captured `SpaceCenter.get_Bodies` value.
    binary =
      <<10, 9, 10, 4, 3, 83, 117, 110, 18, 1, 1, 10, 12, 10, 7, 6, 75, 101, 114, 98, 105, 110, 18,
        1, 2, 10, 9, 10, 4, 3, 77, 117, 110, 18, 1, 3, 10, 12, 10, 7, 6, 77, 105, 110, 109, 117,
        115, 18, 1, 4, 10, 10, 10, 5, 4, 77, 111, 104, 111, 18, 1, 5, 10, 9, 10, 4, 3, 69, 118,
        101, 18, 1, 6, 10, 10, 10, 5, 4, 68, 117, 110, 97, 18, 1, 7, 10, 9, 10, 4, 3, 73, 107,
        101, 18, 1, 8, 10, 10, 10, 5, 4, 74, 111, 111, 108, 18, 1, 9, 10, 12, 10, 7, 6, 76, 97,
        121, 116, 104, 101, 18, 1, 10, 10, 10, 10, 5, 4, 86, 97, 108, 108, 18, 1, 11, 10, 9, 10,
        4, 3, 66, 111, 112, 18, 1, 12, 10, 10, 10, 5, 4, 84, 121, 108, 111, 18, 1, 13, 10, 11, 10,
        6, 5, 71, 105, 108, 108, 121, 18, 1, 14, 10, 9, 10, 4, 3, 80, 111, 108, 18, 1, 15, 10, 10,
        10, 5, 4, 68, 114, 101, 115, 18, 1, 16, 10, 11, 10, 6, 5, 69, 101, 108, 111, 111, 18, 1,
        17>>

    assert %{} = bodies = Types.decode(binary, type, :dummy_conn)
    assert Enum.count(bodies) == 17

    Enum.each(bodies, fn {name, body} ->
      assert String.printable?(name)
      assert %ObjectReference{class: "CelestialBody", conn: :dummy_conn} = body
    end)

    assert Map.fetch!(bodies, "Kerbin").id == <<2>>
    assert Map.fetch!(bodies, "Mun").id == <<3>>
  end

  # I don't believe this is used anywhere in the API, but we support it.
  test "dictionary type encoding" do
    type =
      API.Type.parse(%{
        "code" => "DICTIONARY",
        "types" => [
          %{"code" => "STRING"},
          %{"code" => "BOOL"}
        ]
      })

    map = %{"true_" => true, "false" => false}

    assert <<first::bytes-size(13), second::bytes-size(13)>> = Types.encode(map, type)
    assert <<10, 11, 10, 6, 5, "false", 18, 1, 0>> in [first, second]
    assert <<10, 11, 10, 6, 5, "true_", 18, 1, 1>> in [first, second]
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

  # These only occur in parameters, never in return values.
  test "procedure call type (encode only)" do
    type = API.Type.parse(%{"code" => "PROCEDURE_CALL"})
    proc = SpaceEx.SpaceCenter.rpc_save(:dummy_conn, "SaveName")

    assert Types.encode(proc, type) ==
             <<10, 11, "SpaceCenter", 18, 4, "Save", 26, 13, 8, 0, 18, 9, 8, "SaveName">>
  end

  test "protobuf type" do
    type = API.Type.parse(%{"code" => "STATUS"})

    binary =
      <<10, 5, 48, 46, 52, 46, 51, 16, 139, 3, 24, 255, 5, 37, 11, 255, 0, 30, 45, 0, 216, 212,
        30, 48, 9, 61, 29, 101, 206, 27, 72, 168, 70, 80, 1, 88, 1, 96, 232, 7, 109, 17, 164, 132,
        58, 117, 128, 39, 131, 58, 125, 204, 6, 141, 18, 157, 1, 4, 145, 223, 54>>

    assert %SpaceEx.Protobufs.Status{} = status = Types.decode(binary, type, nil)
    assert status.version == "0.4.3"
    assert status.bytes_written == 767

    # Protobuf types are never actually used in function parameters,
    # but we have an encoder so we may as well test this.
    # Note that you can't use `binary` from above, since that binary is wire-captured,
    # and there's some differences (probably due to ordering changes) in encode.
    assert Types.encode(status, type) == SpaceEx.Protobufs.Status.encode(status)
  end

  test "nested types" do
    inner_type = %{
      "code" => "TUPLE",
      "types" => [%{"code" => "BYTES"}, %{"code" => "STRING"}, %{"code" => "STRING"}]
    }

    type = API.Type.parse(%{"code" => "LIST", "types" => [inner_type]})

    # Wire-captured `KRPC.get_Clients` value.
    binary =
      <<10, 49, 10, 17, 16, 7, 16, 24, 194, 201, 63, 157, 74, 134, 236, 109, 146, 112, 26, 30, 39,
        10, 13, 12, 70, 105, 114, 115, 116, 32, 99, 108, 105, 101, 110, 116, 10, 13, 12, 49, 57,
        50, 46, 49, 54, 56, 46, 54, 56, 46, 51, 10, 50, 10, 17, 16, 236, 32, 29, 221, 11, 93, 19,
        67, 130, 214, 237, 212, 104, 135, 192, 132, 10, 14, 13, 83, 101, 99, 111, 110, 100, 32,
        99, 108, 105, 101, 110, 116, 10, 13, 12, 49, 57, 50, 46, 49, 54, 56, 46, 54, 56, 46, 51>>

    assert [first, second] = list = Types.decode(binary, type, nil)
    assert {<<7, 16, 24, _::bytes-size(13)>>, "First client", "192.168.68.3"} = first
    assert {<<236, 32, 29, _::bytes-size(13)>>, "Second client", "192.168.68.3"} = second

    assert Types.encode(list, type) == binary
  end
end
