defmodule SpaceEx.API.Type.Raw do
  alias SpaceEx.{Util, Protobufs}
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(module: nil)

  @types Protobufs.Raw.defs()
         |> Enum.map(fn {{:msg, module}, _} -> module end)
         |> Enum.reject(&is_nil/1)
         |> Map.new(fn module ->
           code =
             Util.module_basename(module)
             |> String.upcase()

           {code, module}
         end)

  def parse(code) do
    if module = Map.get(@types, code) do
      %Type.Raw{module: module}
    else
      nil
    end
  end
end
