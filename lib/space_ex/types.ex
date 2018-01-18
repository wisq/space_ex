defmodule SpaceEx.Types do
  alias SpaceEx.API.Type
  alias SpaceEx.Protobufs

  @moduledoc false

  defdelegate decode(bytes, type), to: SpaceEx.Types.Decoders
  defdelegate encode(value, type), to: SpaceEx.Types.Encoders

  def encode_enumeration_value(value) do
    encode(value, %Type.Raw{module: Protobufs.Raw.SInt32})
  end
end
