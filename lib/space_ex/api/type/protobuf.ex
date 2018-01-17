defmodule SpaceEx.API.Type.Protobuf do
  alias SpaceEx.{Util, Protobufs}
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(module: nil)

  @types (
    Protobufs.defs
    |> Enum.map(fn
      {{:msg, module}, _} -> module
      {{:enum, _}, _} -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn module ->
      code =
        Util.module_basename(module)
        |> Util.to_snake_case
        |> String.upcase

      {code, module}
    end)
  )

  def parse(code) do
    if module = Map.get(@types, code) do
      %Type.Protobuf{module: module}
    else
      nil
    end
  end
end
