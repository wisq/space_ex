defmodule SpaceEx.API.Class do
  alias SpaceEx.API.{Class, Procedure}

  @moduledoc false

  defstruct(
    name: nil,
    documentation: nil,
    procedures: nil
  )

  def parse(name, json, class_procedures) do
    procedures =
      class_procedures
      |> Enum.map(&Procedure.parse(&1, name))

    %Class{
      name: name,
      documentation: Map.fetch!(json, "documentation"),
      procedures: procedures
    }
  end
end
