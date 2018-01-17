defmodule SpaceEx.Types.Encoders do
  alias SpaceEx.API.Type
  alias SpaceEx.Protobufs

  @moduledoc false

  def encode(value, %Type.Raw{module: module}) do
    <<_first_byte, rest :: bitstring>> =
      module.new(value: value)
      |> module.encode
    rest
  end

  def encode(value, %Type.Protobuf{module: module}) do
    module.encode(value)
  end

  def encode(value, %Type.List{subtype: subtype}) do
    items = Enum.map(value, &encode(&1, subtype))

    Protobufs.List.new(items: items)
    |> Protobufs.List.encode
  end

  def encode(value, %Type.Tuple{subtypes: subtypes}) do
    items =
      Tuple.to_list(value)
      |> encode_tuple(subtypes)

    Protobufs.Tuple.new(items: items)
    |> Protobufs.Tuple.encode
  end

  # TODO: struct containing both reference (`bytes`) and conn
  def encode(value, %Type.Class{}), do: value

  defp encode_tuple([], []), do: []
  defp encode_tuple([item | items], [type | types]) do
    [encode(item, type) | encode_tuple(items, types)]
  end
end
