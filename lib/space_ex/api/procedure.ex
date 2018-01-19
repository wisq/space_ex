defmodule SpaceEx.API.Procedure do
  alias SpaceEx.API.{Procedure, Type}

  @moduledoc false

  defmodule Parameter do
    @moduledoc false

    defstruct(
      name: nil,
      index: nil,
      type: nil,
      default: nil
    )
  end

  defstruct(
    name: nil,
    fn_name: nil,
    fn_arity: nil,
    doc_name: nil,
    documentation: nil,
    return_type: nil,
    positional_params: nil,
    optional_params: nil,
    is_object_method: nil
  )

  def parse({name, json}, class_name) do
    doc_name = strip_rpc_name(name, class_name)
    fn_name = make_fn_name(doc_name)

    parameters =
      Map.fetch!(json, "parameters")
      |> Enum.with_index()
      |> Enum.map(&parse_parameter/1)

    {mandatory, optional} = Enum.split_with(parameters, fn p -> is_nil(p.default) end)
    is_method = is_object_method?(mandatory)
    fn_arity = get_fn_arity(mandatory, optional, is_method: is_method)

    return_type =
      if t = Map.get(json, "return_type") do
        Type.parse(t)
      else
        nil
      end

    %Procedure{
      name: name,
      fn_name: fn_name,
      fn_arity: fn_arity,
      doc_name: doc_name,
      documentation: Map.fetch!(json, "documentation"),
      return_type: return_type,
      positional_params: mandatory,
      optional_params: optional,
      is_object_method: is_method
    }
  end

  defp is_object_method?(params) do
    Enum.any?(params, fn
      %Parameter{name: "this", index: 0} -> true
      _ -> false
    end)
  end

  # Add one for `conn` parameter (at start).
  defp get_fn_arity(mandatory, optional, is_method: false),
    do: get_fn_arity(mandatory, optional) + 1

  # No extra parameters.
  defp get_fn_arity(mandatory, optional, is_method: true), do: get_fn_arity(mandatory, optional)
  # No extra parameters.
  defp get_fn_arity(mandatory, []), do: Enum.count(mandatory)
  # Add one for `opts` parameter (at end).
  defp get_fn_arity(mandatory, _optional), do: Enum.count(mandatory) + 1

  defp make_fn_name(stripped_name) do
    SpaceEx.Util.to_snake_case(stripped_name)
    |> String.to_atom()
  end

  defp strip_rpc_name(rpc_name, nil) do
    String.replace(rpc_name, ~r{^(?:get|static)_}, "")
  end

  defp strip_rpc_name(rpc_name, class_name) do
    prefix = "#{class_name}_"

    case String.split_at(rpc_name, String.length(prefix)) do
      {^prefix, suffix} ->
        strip_rpc_name(suffix, nil)

      _ ->
        raise "Unexpected function #{rpc_name} for class #{class_name}"
    end
  end

  defp parse_parameter({json, index}) do
    type =
      Map.fetch!(json, "type")
      |> Type.parse()

    %Parameter{
      name: Map.fetch!(json, "name"),
      index: index,
      type: type,
      default: Map.get(json, "default_value") |> parse_default_value
    }
  end

  defp parse_default_value(nil), do: nil

  defp parse_default_value(str) do
    {:ok, binary} = Base.decode64(str)
    binary
  end
end
