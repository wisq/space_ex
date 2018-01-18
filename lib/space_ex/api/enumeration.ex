defmodule SpaceEx.API.Enumeration do
  alias SpaceEx.API.Enumeration

  @moduledoc false

  defmodule Value do
    @moduledoc false

    defstruct(
      name: nil,
      atom: nil,
      documentation: nil,
      value: nil
    )
  end

  defstruct(
    name: nil,
    documentation: nil,
    values: nil
  )

  def parse({name, json}) do
    values =
      Map.fetch!(json, "values")
      |> Enum.map(&parse_value/1)

    %Enumeration{
      name: name,
      documentation: Map.fetch!(json, "documentation"),
      values: values
    }
  end

  defp parse_value(%{"name" => name, "value" => value, "documentation" => doc}) do
    %Value{
      name: name,
      atom: SpaceEx.Util.to_snake_case(name) |> String.to_atom(),
      documentation: doc,
      value: value
    }
  end
end
