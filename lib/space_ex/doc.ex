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

  defp process_html({"doc", [], contents}), do: process_html(contents)
  defp process_html({"summary", [], contents}), do: process_html(contents)

  defp process_html({"see", opts, _} = element) do
    [{"cref", ref}] = opts

    case ref do
      <<"M:", method :: bitstring>> ->
        parts = String.split(method, ".")
        {getter, mod_parts} = List.pop_at(parts, -1)

        mod_name = ["SpaceEx" | mod_parts] |> Enum.join(".")
        fn_name = "get_#{SpaceEx.Service.to_snake_case(getter)}"

        "`#{mod_name}`.`#{fn_name}`" # FIXME: get arity so we can do a proper link

      _ -> element
    end
  end

  defp process_html(list) when is_list(list) do
    Enum.map(list, &process_html/1)
    |> List.flatten
  end

  defp process_html(x) do
    x
  end

  defp split_first_sentence(text) do
    String.split(text, ~r{(?<=\.)\s+}, parts: 2)
  end
end
