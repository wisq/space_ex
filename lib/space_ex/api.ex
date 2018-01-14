defmodule SpaceEx.API do
  @moduledoc false

  @api_path Path.expand("api", __DIR__)

  @services (
    File.ls!(@api_path)
    |> Enum.filter(&String.match?(&1, ~r{^KRPC(\..*)?\.json$}))
    |> Enum.map(&Path.expand(&1, @api_path))
    |> Enum.map(&File.read!/1)
    |> Enum.map(&Poison.decode!/1)
    |> Enum.map(&Enum.to_list/1)
    |> List.flatten
    |> Map.new
  )

  def service_names, do: Map.keys(@services)
  def service_data(name), do: Map.fetch!(@services, name)

  def rpc_arity(service_name, procedure_name) do
    procedure =
      service_data(service_name)
      |> Map.fetch!("procedures")
      |> Map.get(procedure_name)

    case procedure do
      %{"parameters" => params} -> Enum.count(params)
      nil -> nil
    end
  end

  def enum_value_exists?(service_name, enum_name, value_name) do
    enum =
      service_data(service_name)
      |> Map.fetch!("enumerations")
      |> Map.get(enum_name)

    case enum do
      %{"values" => values} ->
        Enum.any?(values, fn val ->
          Map.fetch!(val, "name") == value_name
        end)

      nil -> false
    end
  end
end
