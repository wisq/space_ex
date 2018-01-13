defmodule SpaceEx.Types.Encoders do
  alias SpaceEx.Protobufs.Raw

  def type_encoder(input, :BYTES, _opts),  do: input
  def type_encoder(input, :CLASS, _opts),  do: input

  # Strings can also be encoded via:
  #quote do
  #  size = byte_size(str) |> :gpb.encode_varint
  #  size <> str
  #end
  def type_encoder(input, :STRING, _opts), do: raw_encoder(input, Raw.String)
  def type_encoder(input, :FLOAT, _opts),  do: raw_encoder(input, Raw.Float)
  def type_encoder(input, :DOUBLE, _opts), do: raw_encoder(input, Raw.Double)
  def type_encoder(input, :SINT32, _opts), do: raw_encoder(input, Raw.SInt32)
  def type_encoder(input, :UINT32, _opts), do: raw_encoder(input, Raw.UInt32)
  def type_encoder(input, :UINT64, _opts), do: raw_encoder(input, Raw.UInt64)

  def type_encoder(input, :BOOL, _opts) do
    quote do
      case unquote(input) do
        false -> <<0>>
        true  -> <<1>>
      end
    end
  end

  def type_encoder(input, type, _opts) do
    if module = SpaceEx.Types.protobuf_module(type) do
      quote do: unquote(module).encode(unquote(input))
    else
      raise "No Protobuf module found for type #{type}"
    end
  end


  def raw_encoder(input, module) do
    quote do
      unquote(module).new(value: unquote(input))
      |> unquote(module).encode
      |> SpaceEx.Types.Encoders.strip_first_byte
    end
  end


  def pre_encode(:LIST, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      Enum.map(fn item ->
        SpaceEx.Types.encode(item, unquote(subtype))
      end)
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.List.new
    end
  end

  def pre_encode(:SET, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      Enum.map(fn item ->
        SpaceEx.Types.encode(item, unquote(subtype))
      end)
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.Set.new
    end
  end

  def pre_encode(:TUPLE, subtypes, _opts) do
    encoders = Enum.map(subtypes, fn subtype ->
      quote do
        fn item ->
          SpaceEx.Types.encode(item, unquote(subtype))
        end
      end
    end)

    quote do
      SpaceEx.Types.Encoders.encode_tuple(unquote(encoders))
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.Tuple.new
    end
  end

  def pre_encode(:DICTIONARY, subtypes, _opts) do
    [key_type, value_type] = subtypes

    quote do
      Enum.each(fn {key, value} ->
        SpaceEx.Protobufs.DictionaryEntry.new(
          key:   SpaceEx.Types.encode(key, unquote(key_type)),
          value: SpaceEx.Types.encode(value, unquote(value_type)),
        )
      end)
      |> SpaceEx.Types.Encoders.build_map(:entries)
      |> SpaceEx.Protobufs.Dictionary.new
    end
  end

  def pre_encode(code, types, _opts) when is_list(types) do
    raise "Unknown type code with subtypes: #{inspect(code)}"
  end

  def pre_encode(_, _, _), do: nil


  def encode_tuple(tuple, encoders) do
    Tuple.to_list(tuple)
    |> Enum.zip(encoders)
    |> Enum.map(fn {item, encoder} -> encoder.(item) end)
  end

  def strip_first_byte(<<_byte, rest :: binary>>), do: rest

  def build_map(value, key), do: %{key => value}
end
