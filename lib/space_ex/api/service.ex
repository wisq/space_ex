defmodule SpaceEx.API.Service do
  alias SpaceEx.API.{Service, Class, Procedure, Enumeration}

  @moduledoc false

  defstruct(
    name: nil,
    documentation: nil,
    classes: nil,
    enumerations: nil,
    procedures: nil,
  )

  def parse({name, json}) do
    proc_by_class = procedures_by_class(json)

    classes =
      Map.fetch!(json, "classes")
      |> Enum.map(fn {class_name, class_json} ->
        procs = Map.get(proc_by_class, class_name, [])
        Class.parse(class_name, class_json, procs)
      end)

    procedures =
      Map.fetch!(proc_by_class, :no_class)
      |> Enum.map(&Procedure.parse(&1, nil))

    enumerations =
      Map.fetch!(json, "enumerations")
      |> Enum.map(&Enumeration.parse/1)

    %Service{
      name: name,
      documentation: Map.fetch!(json, "documentation"),
      classes: classes,
      enumerations: enumerations,
      procedures: procedures,
    }
  end

  # Returns %{:no_class => [...], "Class1" => [...], "Class2" => [...], ...}
  defp procedures_by_class(json) do
    class_names =
      Map.fetch!(json, "classes")
      |> Enum.map(fn {name, _} -> name end)
    procedures = Map.fetch!(json, "procedures")

    [:no_class | class_names]
    |> Map.new(fn class ->
      {class, class_procedures(class, procedures, class_names)}
    end)
  end

  # Find procedures without any class.
  def class_procedures(:no_class, procedures, class_names) do
    Enum.reject(procedures, fn {proc_name, _} ->
      Enum.any?(class_names, fn class_name ->
        String.starts_with?(proc_name, "#{class_name}_")
      end)
    end)
  end

  # Find procedures for a particular class.
  def class_procedures(class_name, procedures, _class_names) do
    Enum.filter(procedures, fn {proc_name, _} ->
      String.starts_with?(proc_name, "#{class_name}_")
    end)
  end
end
