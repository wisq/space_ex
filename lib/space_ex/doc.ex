defmodule SpaceEx.Doc.DescribeType do
  defmacro def_describe_type(pattern, one: singular, many: plural, short: short) do
    quote do
      defp describe_type(:one, unquote(pattern)), do: {unquote(singular), []}
      defp describe_type(:many, unquote(pattern)), do: {unquote(plural), []}
      defp describe_type(:short, unquote(pattern)), do: {unquote(short), []}
    end
  end
end

defmodule SpaceEx.Doc.Indexer do
  alias SpaceEx.API

  @moduledoc false

  def build do
    API.services()
    |> Enum.map(&index_service/1)
    |> List.flatten()
    |> Map.new()
  end

  defp index_service(service) do
    [
      service.enumerations
      |> Enum.map(&index_enumeration(service, &1)),
      service.procedures
      |> Enum.map(&index_procedure(service.name, &1)),
      service.classes
      |> Enum.map(&index_class(service, &1))
    ]
  end

  defp index_enumeration(service, enumeration) do
    module = "#{service.name}.#{enumeration.name}"

    [
      {"T:#{module}", "SpaceEx.#{module}"},
      Enum.map(enumeration.values, fn ev ->
        {"M:#{module}.#{ev.name}", "SpaceEx.#{module}.#{ev.atom}"}
      end)
    ]
  end

  defp index_procedure(module_name, procedure) do
    {
      "M:#{module_name}.#{procedure.doc_name}",
      "SpaceEx.#{module_name}.#{procedure.fn_name}/#{procedure.fn_arity}"
    }
  end

  defp index_class(service, class) do
    module = "#{service.name}.#{class.name}"

    [
      {"T:#{module}", "SpaceEx.#{module}"},
      Enum.map(class.procedures, &index_procedure(module, &1))
    ]
  end
end

defmodule SpaceEx.Doc do
  alias SpaceEx.Util
  alias SpaceEx.API.Type
  require SpaceEx.Doc.DescribeType
  import SpaceEx.Doc.DescribeType

  @moduledoc false

  @reference_index SpaceEx.Doc.Indexer.build()

  def service(obj) do
    extract_documentation(obj)
  end

  def class(obj) do
    extract_documentation(obj)
  end

  def procedure(obj) do
    extract_documentation(obj)
    |> document_return_type(obj.return_type)
  end

  def enumeration(obj) do
    extract_documentation(obj)
  end

  def enumeration_value(obj) do
    doc = extract_documentation(obj)
    "#{doc}\n\n**Returns:** `#{inspect(obj.atom)}`"
  end

  defp document_return_type(doc, nil) do
    doc <> "\n\n**Returns:** `:ok`"
  end

  defp document_return_type(doc, type) do
    {desc, where} = describe_type(:one, type)

    if Enum.empty?(where) do
      doc <> "\n\n**Returns:** #{desc}"
    else
      parts =
        where
        |> Enum.uniq_by(fn {short, _} -> short end)
        |> Enum.map(fn {short, subdesc} -> "`#{short}` is #{subdesc}" end)
        |> Util.join_words("and")

      doc <> "\n\n**Returns:** #{desc}, where #{parts}"
    end
  end

  defp short_module(module) do
    Util.module_basename(module)
    |> Util.to_snake_case()
  end

  def_describe_type(
    %Type.Class{module: module},
    one: "a reference to a `#{inspect(module)}` object",
    many: "references to `#{inspect(module)}` objects",
    short: short_module(module)
  )

  def_describe_type(
    %Type.Enumeration{module: module},
    one: "a `#{module}` value in atom form",
    many: "`#{module}` values in atom form",
    short: short_module(module)
  )

  def_describe_type(
    %Type.Raw{code: "BOOL"},
    one: "`true` or `false`",
    many: "`true` or `false` values",
    short: "bool"
  )

  def_describe_type(
    %Type.Raw{code: "FLOAT"},
    one: "a low-precision decimal",
    many: "low-precision decimals",
    short: "float"
  )

  def_describe_type(
    %Type.Raw{code: "DOUBLE"},
    one: "a high precision decimal",
    many: "high precision decimals",
    short: "double"
  )

  def_describe_type(
    %Type.Raw{code: "STRING"},
    one: "a string",
    many: "strings",
    short: "str"
  )

  def_describe_type(
    %Type.Raw{code: "BYTES"},
    one: "a string of binary bytes",
    many: "strings of binary bytes",
    short: "bytes"
  )

  def_describe_type(
    %Type.Raw{code: "SINT32"},
    one: "an integer",
    many: "integers",
    short: "int"
  )

  def_describe_type(
    %Type.Protobuf{module: SpaceEx.Protobufs.Services},
    one: "a nested structure describing available services",
    many: "nested structures describing available services",
    short: "services"
  )

  def_describe_type(
    %Type.Protobuf{module: SpaceEx.Protobufs.Status},
    one: "a structure with internal server details",
    many: "structures with internal server details",
    short: "status"
  )

  defp describe_nested_types(subtypes) do
    {shorts, sub_wheres} =
      Enum.map(subtypes, fn subtype ->
        {short, short_where} = describe_type(:short, subtype)

        if Enum.empty?(short_where) do
          # A plain value: describe it.
          {desc, _where} = describe_type(:one, subtype)
          {short, [{short, desc} | short_where]}
        else
          # A nested value: include its `where` definitions, but don't describe it.
          {short, short_where}
        end
      end)
      |> Enum.unzip()

    where = List.flatten(sub_wheres)
    {shorts, where}
  end

  defp describe_type(mode, %Type.Tuple{subtypes: subtypes}) do
    {shorts, where} = describe_nested_types(subtypes)

    short = "{" <> Enum.join(shorts, ", ") <> "}"

    case mode do
      :short -> {short, where}
      _ -> {"`#{short}`", where}
    end
  end

  defp describe_type(mode, %Type.List{subtype: subtype}) do
    {[short], where} = describe_nested_types([subtype])

    short = "[#{short}, ...]"

    case mode do
      :short -> {short, where}
      _ -> {"`#{short}`", where}
    end
  end

  defp describe_type(mode, %Type.Set{subtype: subtype}) do
    {[short], where} = describe_nested_types([subtype])

    short = "MapSet.new([#{short}, ...])"

    case mode do
      :short -> {short, where}
      _ -> {"`#{short}`", where}
    end
  end

  defp describe_type(mode, %Type.Dictionary{key_type: k_t, value_type: v_t}) do
    {[key, value], where} = describe_nested_types([k_t, v_t])

    short = "%{#{key} => #{value}, ...}"

    case mode do
      :short -> {short, where}
      _ -> {"`#{short}`", where}
    end
  end

  defp extract_documentation(obj) do
    text =
      obj.documentation
      |> Floki.parse()
      |> process_html
      |> Floki.raw_html()
      |> HtmlEntities.decode()
      |> String.trim()

    split_first_sentence(text)
    |> Enum.join("\n\n")
  end

  # Strip these HTML tags entirely:
  defp process_html({"doc", [], contents}), do: process_html(contents)
  defp process_html({"list", _opts, contents}), do: process_html(contents)
  defp process_html({"description", [], contents}), do: process_html(contents)
  defp process_html({"remarks", [], contents}), do: process_html(contents)

  # Pass these HTML tags through:
  defp process_html({"a" = name, opts, contents}), do: {name, opts, process_html(contents)}

  # The remaining tags get special processing.

  defp process_html({"summary", [], contents}) do
    process_html(contents) ++ ["\n\n"]
  end

  # The heck are these?
  defp process_html({"returns", [], []}), do: []

  defp process_html({"returns", [], [first | rest]}) when is_bitstring(first) do
    contents = [de_capitalize(first) | rest]
    ["\n\nReturns " | process_html(contents)]
  end

  defp process_html({"returns", [], contents}) do
    raise "Weird <returns> contents: #{inspect(contents)}"
  end

  defp process_html({"param", opts, contents}) do
    [{"name", name}] = opts
    name = Util.to_snake_case(name)
    ["\n * `#{name}` — "] ++ process_html(contents) ++ ["\n"]
  end

  defp process_html({"paramref", opts, []}) do
    [{"name", name}] = opts
    "`#{name}`"
  end

  defp process_html({"c", [], [content]}) do
    case content do
      "null" -> "`nil`"
      _ -> "`#{content}`"
    end
  end

  defp process_html({"item", [], contents}) do
    ["\n * "] ++ process_html(contents) ++ ["\n"]
  end

  defp process_html({"math", [], contents}) do
    {"span", [class: "math"], ["\\\\("] ++ process_html(contents) ++ ["\\\\)"]}
  end

  defp process_html({"see", opts, _} = element) do
    [{"cref", ref}] = opts

    if value = Map.get(@reference_index, ref) do
      "`#{value}`"
    else
      raise "Unknown <see> cref: #{inspect(element)}"
    end
  end

  defp process_html(list) when is_list(list) do
    Enum.map(list, &process_html/1)
    |> List.flatten()
  end

  defp process_html({name, _, contents}) do
    IO.puts("Unknown HTML element stripped: #{inspect(name)}")
    process_html(contents)
  end

  defp process_html(text) when is_bitstring(text), do: text

  defp split_first_sentence(text) do
    String.split(text, ~r{(?<=\.)\s+}, parts: 2)
  end

  defp de_capitalize(<<"The ", rest::bitstring>>), do: "the #{rest}"
  defp de_capitalize(<<"A ", rest::bitstring>>), do: "a #{rest}"
  defp de_capitalize(<<"An ", rest::bitstring>>), do: "an #{rest}"

  defp de_capitalize(string) do
    case Regex.run(~r/^([A-Z][a-z]+)(\s.*)$/, string) do
      [_, word, rest] -> String.downcase(word) <> rest
      nil -> string
    end
  end
end
