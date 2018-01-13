defmodule SpaceEx.Types.Decoders do
  alias SpaceEx.Protobufs.Raw

  def type_decoder(input, :BYTES, _opts),  do: input
  # TODO: maybe render classes as structs?
  def type_decoder(input, :CLASS, _opts),  do: input

  # Strings can also be decoded via:
  #quote do
  #  {size, str} = :gpb.decode_varint(unquote(input))
  #  <<_str :: bytes-size(size)>> = str
  #end
  def type_decoder(input, :STRING, _opts), do: raw_decoder(input, Raw.String, "dummy")
  def type_decoder(input, :FLOAT, _opts),  do: raw_decoder(input, Raw.Float, 1.23)
  def type_decoder(input, :DOUBLE, _opts), do: raw_decoder(input, Raw.Double, 1.23)
  def type_decoder(input, :SINT32, _opts), do: raw_decoder(input, Raw.SInt32, 123)

  def type_decoder(input, :BOOL, _opts) do
    quote do
      case unquote(input) do
        <<0>> -> false
        <<1>> -> true
      end
    end
  end

  def type_decoder(input, type, _opts) do
    if module = SpaceEx.Types.protobuf_module(type) do
      quote do: unquote(module).decode(unquote(input))
    else
      raise "No Protobuf module found for type #{type}"
    end
  end


  def raw_decoder(input, module, example) do
    <<first_byte, _ :: binary>> =
      module.new(value: example)
      |> module.encode

    quote do
      <<unquote(first_byte)>> <> unquote(input)
      |> unquote(module).decode
      |> Map.fetch!(:value)
    end
  end


  def post_decode(:LIST, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      Map.fetch!(:items)
      |> Enum.map(fn item ->
        SpaceEx.Types.decode(item, unquote(subtype))
      end)
    end
  end

  def post_decode(:SET, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      Map.fetch!(:items)
      |> MapSet.new(fn item ->
        SpaceEx.Types.decode(item, unquote(subtype))
      end)
    end
  end

  def post_decode(:TUPLE, subtypes, _opts) do
    decoders = Enum.map(subtypes, fn subtype ->
      quote do
        fn item ->
          SpaceEx.Types.decode(item, unquote(subtype))
        end
      end
    end)

    quote do
      Map.fetch!(:items)
      |> SpaceEx.Types.Decoders.decode_tuple(unquote(decoders))
    end
  end

  def post_decode(:DICTIONARY, subtypes, _opts) do
    [key_type, value_type] = subtypes

    quote do
      Map.fetch!(:entries)
      |> Map.new(fn entry ->
        {
          SpaceEx.Types.decode(entry.key, unquote(key_type)),
          SpaceEx.Types.decode(entry.value, unquote(value_type)),
        }
      end)
    end
  end

  def post_decode(code, types, _opts) when is_list(types) do
    raise "Unknown type code with subtypes: #{inspect(code)}"
  end

  def post_decode(_, _, _), do: nil


  def decode_tuple(items, decoders) do
    Enum.zip(items, decoders)
    |> Enum.map(fn {item, decoder} -> decoder.(item) end)
    |> List.to_tuple
  end
end
