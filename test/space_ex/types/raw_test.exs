defmodule SpaceEx.Types.RawTest do
  use ExUnit.Case, async: true
  alias SpaceEx.{API, Types}

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
end
