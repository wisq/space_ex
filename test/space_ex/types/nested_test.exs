defmodule SpaceEx.Types.NestedTest do
  use ExUnit.Case, async: true
  alias SpaceEx.{API, Types, ObjectReference}

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

  # Combined test using real data.
  test "nested list and tuple using wire data" do
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
