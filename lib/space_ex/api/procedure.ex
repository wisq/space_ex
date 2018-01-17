defmodule SpaceEx.API.Procedure do
  alias SpaceEx.API.Procedure

  @moduledoc false

  defmodule Parameter do
    defstruct(
      name: nil,
      index: nil,
      type: nil,
      default: nil,
    )
  end

  defstruct(
    name: nil,
    documentation: nil,
    parameters: nil,
  )

  def parse({name, json}) do
    parameters =
      Map.fetch!(json, "parameters")
      |> Enum.with_index
      |> Enum.map(&parse_parameter/1)

    %Procedure{
      name: name,
      documentation: Map.fetch!(json, "documentation"),
      parameters: parameters,
    }
    |> IO.inspect
  end

  defp parse_parameter({json, index}) do
    %Parameter{
      name: Map.fetch!(json, "name"),
      index: index,
      default: Map.get(json, "default_value") |> parse_default_value,
    }
  end

  def parse_default_value(nil), do: nil

  def parse_default_value(str) do
    {:ok, binary} = Base.decode64(str)
    binary
  end
end
