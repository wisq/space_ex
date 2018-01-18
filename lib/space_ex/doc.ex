defmodule SpaceEx.Doc.Indexer do
  alias SpaceEx.API

  @moduledoc false

  def build do
    API.services
    |> Enum.map(&index_service/1)
    |> List.flatten
    |> Map.new
  end

  defp index_service(service) do
    [
      service.enumerations
      |> Enum.map(&index_enumeration(service, &1)),

      service.procedures
      |> Enum.map(&index_procedure(service.name, &1)),

      service.classes
      |> Enum.map(&index_class(service, &1)),
    ]
  end

  defp index_enumeration(service, enumeration) do
    module = "#{service.name}.#{enumeration.name}"
    [
      {"T:#{module}", "SpaceEx.#{module}"},

      Enum.map(enumeration.values, fn ev ->
        {"M:#{module}.#{ev.name}", "SpaceEx.#{module}.#{ev.atom}"}
      end),
    ]
  end

  defp index_procedure(module_name, procedure) do
    arity = Enum.count(procedure.parameters) + 1
    {
      "M:#{module_name}.#{procedure.doc_name}", 
      "SpaceEx.#{module_name}.#{procedure.fn_name}/#{arity}", 
    }
  end

  defp index_class(service, class) do
    module = "#{service.name}.#{class.name}"
    [
      {"T:#{module}", "SpaceEx.#{module}"},

      Enum.map(class.procedures, &index_procedure(module, &1)),
    ]
  end
end

defmodule SpaceEx.Doc do
  @moduledoc false

  @reference_index SpaceEx.Doc.Indexer.build

  def service(obj) do
    extract_documentation(obj)
  end

  def class(obj) do
    extract_documentation(obj)
  end

  def procedure(obj) do
    extract_documentation(obj)
  end

  def enumeration(obj) do
    extract_documentation(obj)
  end

  def enumeration_value(obj) do
    doc = extract_documentation(obj)
    "#{doc}\n\nReturns `#{inspect(obj.atom)}`."
  end

  defp extract_documentation(obj) do
    text =
      obj.documentation
      |> Floki.parse
      |> process_html
      |> Floki.raw_html
      |> String.trim

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

  defp process_html({"returns", [], contents}) do
    ["\n\n**Returns:** " | process_html(contents)]
  end

  defp process_html({"param", opts, contents}) do
    [{"name", name}] = opts
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
    {"span", [class: "math"],
      ["\\\\("] ++ process_html(contents) ++ ["\\\\)"]}
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
    |> List.flatten
  end

  defp process_html({name, _, contents}) do
    IO.puts "Unknown HTML element stripped: #{inspect(name)}"
    process_html(contents)
  end

  defp process_html(text) when is_bitstring(text), do: text

  defp split_first_sentence(text) do
    String.split(text, ~r{(?<=\.)\s+}, parts: 2)
  end
end
