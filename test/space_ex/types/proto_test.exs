defmodule SpaceEx.Types.ProtoTest do
  use ExUnit.Case, async: true
  alias SpaceEx.{API, Types}

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
end
