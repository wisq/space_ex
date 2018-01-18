defmodule SpaceEx.Types.Decoders do
  alias SpaceEx.API.Type
  alias SpaceEx.{Protobufs, ObjectReference}

  @moduledoc false

  [
    {Protobufs.Raw.Bool, true},
    {Protobufs.Raw.Bytes, <<1, 2, 3>>},
    {Protobufs.Raw.String, "dummy"},
    {Protobufs.Raw.Float, 1.23},
    {Protobufs.Raw.Double, 1.23},
    {Protobufs.Raw.SInt32, 123}
  ]
  |> Enum.each(fn {module, example} ->
    <<first_byte, _::binary>> =
      module.new(value: example)
      |> module.encode

    def raw_first_byte(unquote(module)), do: <<unquote(first_byte)>>
  end)

  def decode(bytes, %Type.Raw{module: module}, _conn) do
    bytes = raw_first_byte(module) <> bytes
    module.decode(bytes).value
  end

  def decode(bytes, %Type.Protobuf{module: module}, _conn) do
    module.decode(bytes)
  end

  def decode(bytes, %Type.List{subtype: subtype}, conn) do
    Protobufs.List.decode(bytes).items
    |> Enum.map(&decode(&1, subtype, conn))
  end

  def decode(bytes, %Type.Set{subtype: subtype}, conn) do
    Protobufs.Set.decode(bytes).items
    |> MapSet.new(&decode(&1, subtype, conn))
  end

  def decode(bytes, %Type.Tuple{subtypes: subtypes}, conn) do
    Protobufs.Tuple.decode(bytes).items
    |> decode_tuple(subtypes, conn)
    |> List.to_tuple()
  end

  def decode(bytes, %Type.Dictionary{key_type: key_type, value_type: value_type}, conn) do
    Protobufs.Dictionary.decode(bytes).entries
    |> Map.new(fn entry ->
      {
        decode(entry.key, key_type, conn),
        decode(entry.value, value_type, conn)
      }
    end)
  end

  def decode(bytes, %Type.Enumeration{module: module}, _conn) do
    module.wire_to_atom(bytes)
  end

  def decode(bytes, %Type.Class{name: name}, conn) do
    %ObjectReference{id: bytes, class: name, conn: conn}
  end

  defp decode_tuple([], [], _conn), do: []

  defp decode_tuple([item | items], [type | types], conn) do
    [decode(item, type, conn) | decode_tuple(items, types, conn)]
  end
end
