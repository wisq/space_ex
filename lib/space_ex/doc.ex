defmodule SpaceEx.Doc do
  @moduledoc false

  def service(opts) do
    extract_documentation(opts)
  end

  def class(opts) do
    extract_documentation(opts)
  end

  def procedure(opts) do
    extract_documentation(opts)
  end

  def enumeration(opts) do
    extract_documentation(opts)
  end

  def enumeration_value(opts, returns) do
    doc = extract_documentation(opts)
    "#{doc}\n\nReturns `#{inspect(returns)}`."
  end

  defp extract_documentation(opts) do
    text =
      Map.fetch!(opts, "documentation")
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

    case ref do
      <<"M:", spec :: bitstring>> -> find_method_spec(spec)

      <<"T:", spec :: bitstring>> -> "`SpaceEx.#{spec}`"

      _ -> raise "Unknown <see> cref: #{inspect(element)}"
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

  defp find_method_spec(spec) do
    found =
      case String.split(spec, ".") do
        [service, class, method] ->
          find_method(service, class, method) ||
            find_method(service, class, "get_#{method}") ||
              find_method(service, class, "static_#{method}") ||
                find_enum_value(service, class, method)

        [service, method] ->
          find_method(service, nil, method) ||
            find_method(service, nil, "get_#{method}")
      end

    if found do
      found
    else
      IO.puts "Cannot resolve documentation cross-reference: #{inspect(spec)}"
      "`(unknown)`"
    end
  end

  defp find_method(service, nil = class, method) do
    module_name = "SpaceEx.#{service}"
    find_raw_method(service, method, module_name, class)
  end

  defp find_method(service, class, method) do
    module_name = "SpaceEx.#{service}.#{class}"
    rpc_method = "#{class}_#{method}"
    find_raw_method(service, rpc_method, module_name, class)
  end

  def find_raw_method(service, rpc_name, module_name, class) do
    if arity = SpaceEx.API.rpc_arity(service, rpc_name) do
      fn_name = SpaceEx.Gen.rpc_function_name(rpc_name, class)

      # arity + 1 because args are (conn, *rpc_args)
      "`#{module_name}.#{fn_name}/#{arity + 1}`"
    end
  end

  defp find_enum_value(service, enum, value) do
    if SpaceEx.API.enum_value_exists?(service, enum, value) do
      atom = SpaceEx.Util.to_snake_case(value)

      "`:#{atom}`"
    end
  end
end
