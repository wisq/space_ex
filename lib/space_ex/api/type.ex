defmodule SpaceEx.API.Type do
  alias SpaceEx.API.Type

  @moduledoc false

  def parse(%{"code" => code, "types" => types}) do
    parse_nested(code, types)
  end

  def parse(%{"code" => code} = opts) do
    parse_special(code, opts) ||
      Type.Raw.parse(code) ||
        Type.Protobuf.parse(code) ||
          raise "Unknown type: #{code}"
  end

  @nested_types %{
    "SET" => Type.Set,
    "LIST" => Type.List,
    "TUPLE" => Type.Tuple,
    "DICTIONARY" => Type.Dictionary,
  }

  defp parse_nested(code, subtypes) do
    module = Map.fetch!(@nested_types, code)
    module.parse(code, subtypes)
  end

  @special_types %{
    "CLASS" => Type.Class,
    "PROCEDURE_CALL" => Type.ProcedureCall,
  }

  defp parse_special(code, opts) do
    if module = Map.get(@special_types, code) do
      module.parse(code, opts)
    else
      nil
    end
  end
end
