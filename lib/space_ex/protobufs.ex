defmodule SpaceEx.Protobufs do
  use Protobuf, from: Path.expand("proto/krpc.proto", __DIR__)
  @external_resource  Path.expand("proto/krpc.proto", __DIR__)

  defmodule Raw do
    use Protobuf, from: Path.expand("proto/raw.proto", __DIR__)
    @external_resource  Path.expand("proto/raw.proto", __DIR__)
  end
end
