defmodule SpaceEx.Types.Encoders do
  alias SpaceEx.Protobufs.Raw

  def type_encoder(input, code, %{"types" => subtypes} = opts),
    do: nested_type_encoder(input, code, subtypes, opts)

  def type_encoder(input, :BYTES, _opts),  do: input
  def type_encoder(input, :CLASS, _opts),  do: input

  # FIXME: wtf do I do with this?
  def type_encoder(input, :PROCEDURE_CALL, _opts), do: input

  def type_encoder(input, :ENUMERATION, opts) do
    %{"service" => service, "name" => name} = opts
    module = :"Elixir.SpaceEx.#{service}.#{name}"

    ast = quote do
      unquote(module).value(unquote(input))
    end
    type_encoder(ast, :SINT32, %{})
  end

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


  def raw_encoder(input, module) do
    quote do
      unquote(module).new(value: unquote(input))
      |> unquote(module).encode
      |> SpaceEx.Types.Encoders.strip_first_byte
    end
  end


  def nested_type_encoder(input, :LIST, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      unquote(input)
      |> Enum.map(fn item -> SpaceEx.Types.encode(item, unquote(subtype)) end)
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.List.new
      |> SpaceEx.Protobufs.List.encode
    end
  end

  def nested_type_encoder(input, :SET, subtypes, _opts) do
    [subtype] = subtypes
    quote do
      unquote(input)
      |> Enum.map(fn item -> SpaceEx.Types.encode(item, unquote(subtype)) end)
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.Set.new
      |> SpaceEx.Protobufs.Set.encode
    end
  end

  def nested_type_encoder(input, :TUPLE, subtypes, _opts) do
    encoders = Enum.map(subtypes, fn subtype ->
      quote do
        fn item ->
          SpaceEx.Types.encode(item, unquote(subtype))
        end
      end
    end)

    quote do
      unquote(input)
      |> SpaceEx.Types.Encoders.encode_tuple(unquote(encoders))
      |> SpaceEx.Types.Encoders.build_map(:items)
      |> SpaceEx.Protobufs.Tuple.new
      |> SpaceEx.Protobufs.Tuple.encode
    end
  end

  def nested_type_encoder(input, :DICTIONARY, subtypes, _opts) do
    [key_type, value_type] = subtypes

    quote do
      unquote(input)
      |> Enum.map(fn {key, value} ->
        SpaceEx.Protobufs.DictionaryEntry.new(
          key:   SpaceEx.Types.encode(key, unquote(key_type)),
          value: SpaceEx.Types.encode(value, unquote(value_type)),
        )
      end)
      |> SpaceEx.Types.Encoders.build_map(:entries)
      |> SpaceEx.Protobufs.Dictionary.new
      |> SpaceEx.Protobufs.Dictionary.encode
    end
  end


  def encode_tuple(tuple, encoders) do
    Tuple.to_list(tuple)
    |> Enum.zip(encoders)
    |> Enum.map(fn {item, encoder} -> encoder.(item) end)
  end

  def strip_first_byte(<<_byte, rest :: binary>>), do: rest

  def build_map(value, key), do: %{key => value}
end
