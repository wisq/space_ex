defmodule SpaceEx.Protobufs do
  use Protobuf, from: Path.expand("proto/krpc.proto", __DIR__)
end
