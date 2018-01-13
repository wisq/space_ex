defmodule SpaceEx.Types do
  alias SpaceEx.Protobufs.Raw

  defmacro decode(_input, nil) do
    :ok
  end

  defmacro decode(input, {:%{}, _, tuples}) do
    map = Map.new(tuples)
    decode_ast(input, map)
  end

  def decode_ast(input, %{"code" => "LIST", "types" => [subtype]}) do
    quote location: :keep do
      SpaceEx.Protobufs.List.decode(unquote(input)).items
      |> Enum.map(fn item ->
        SpaceEx.Types.decode(item, unquote(subtype))
      end)
    end
  end

  def decode_ast(input, %{"code" => "SET", "types" => [subtype]}) do
    quote location: :keep do
      SpaceEx.Protobufs.Set.decode(unquote(input)).items
      |> MapSet.new(fn item ->
        SpaceEx.Types.decode(item, unquote(subtype))
      end)
    end
  end

  def decode_ast(input, %{"code" => "TUPLE", "types" => subtypes}) do
    variables =
      Enum.map(?a..?z, fn n ->
        <<n>>
        |> String.to_atom
        |> Macro.var(__MODULE__)
      end)
      |> Enum.take(Enum.count(subtypes))

    decoders =
      Enum.zip(subtypes, variables)
      |> Enum.map(fn {subtype, var} ->
        quote do
          unquote(var) = SpaceEx.Types.decode(unquote(var), unquote(subtype))
        end
      end)

    ast_before = quote do
      unquote(variables) = SpaceEx.Protobufs.Tuple.decode(unquote(input)).items
    end
    ast_after = quote do
      {unquote_splicing(variables)}
    end

    {:__block__, [], [ast_before] ++ decoders ++ [ast_after]}
  end

  def decode_ast(input, %{"code" => "DICTIONARY", "types" => [key_type, value_type]}) do
    quote location: :keep do
      SpaceEx.Protobufs.Dictionary.decode(unquote(input)).entries
      |> Map.new(fn entry ->
        {
          SpaceEx.Types.decode(entry.key, unquote(key_type)),
          SpaceEx.Types.decode(entry.value, unquote(value_type)),
        }
      end)
    end
  end

  def decode_ast(input, %{"code" => "DICTIONARY_ENTRY", "types" => [subtype]}) do
    quote location: :keep do
      SpaceEx.Protobufs.Dictionary.decode(unquote(input)).entries
      |> Map.new(fn item ->
        SpaceEx.Types.decode(item, unquote(subtype))
      end)
    end
  end

  def decode_ast(input, %{"code" => "CLASS", "service" => _service, "name" => _class}) do
    input
  end

  def decode_ast(input, %{"code" => "STRING"}) do
    <<first_byte, _ :: binary>> =
      Raw.String.new(value: "dummy")
      |> Raw.String.encode

    quote do
      Raw.String.decode(<<unquote(first_byte)>> <> unquote(input)).value
    end
    #quote do
    #  {size, str} = :gpb.decode_varint(unquote(input))
    #  <<_str :: bytes-size(size)>> = str
    #end
  end

  def decode_ast(input, %{"code" => "FLOAT"}) do
    <<first_byte, _ :: binary>> =
      Raw.Float.new(value: 123.4)
      |> Raw.Float.encode

    quote do
      Raw.Float.decode(<<unquote(first_byte)>> <> unquote(input)).value
    end
  end

  def decode_ast(input, %{"code" => "DOUBLE"}) do
    <<first_byte, _ :: binary>> =
      Raw.Double.new(value: 123.4)
      |> Raw.Double.encode

    quote do
      Raw.Double.decode(<<unquote(first_byte)>> <> unquote(input)).value
    end
  end

  def decode_ast(input, %{"code" => "SINT32"}) do
    <<first_byte, _ :: binary>> =
      Raw.SInt32.new(value: 123)
      |> Raw.SInt32.encode

    quote do
      Raw.SInt32.decode(<<unquote(first_byte)>> <> unquote(input)).value
    end
  end

  def decode_ast(input, %{"code" => "BOOL"}) do
    quote do
      case unquote(input) do
        <<0>> -> false
        <<1>> -> true
      end
    end
  end

  def decode_ast(input, %{"code" => "BYTES"}), do: input

  def decode_ast(input, %{"code" => code} = opts) do
    if !Map.has_key?(opts, "types") do
      decode_protobuf_ast(input, code)
    else
      nil
    end || decode_unknown_ast(code)
  end

  def decode_unknown_ast(code) do
    IO.puts "Unknown type code: #{code}"
    quote do
      raise "Unknown type code: #{unquote(code)}"
    end
  end

  SpaceEx.Protobufs.defs
  |> Enum.map(&elem(&1, 0))
  |> Enum.filter(fn {type, _} -> type == :msg end)
  |> Enum.each(fn {_, module} ->
    type_code =
      module
      |> SpaceEx.Service.module_basename
      |> SpaceEx.Service.to_snake_case
      |> String.upcase

    def decode_protobuf_ast(input, unquote(type_code)) do
      module = unquote(module)
      quote do
        unquote(module).decode(unquote(input))
      end
    end
  end)

  def decode_protobuf_ast(_, _), do: nil
end
