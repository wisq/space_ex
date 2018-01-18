defmodule SpaceEx.API do
  @moduledoc false

  @api_path Path.expand("api/json", __DIR__)

  @service_files (
    File.ls!(@api_path)
    |> Enum.filter(&String.match?(&1, ~r{^KRPC(\..*)?\.json$}))
    |> Enum.map(&Path.expand(&1, @api_path))
  )

  Enum.each(@service_files, fn file ->
    @external_resource file
  end)

  @services (
    @service_files
    |> Enum.map(&File.read!/1)
    |> Enum.map(&Poison.decode!/1)
    |> Enum.map(&Enum.to_list/1)
    |> List.flatten
    |> Enum.map(&SpaceEx.API.Service.parse/1)
    |> Map.new(fn service -> {service.name, service} end)
  )

  def services, do: Map.values(@services)
  def service_names, do: Map.keys(@services)
  def service_data(name), do: Map.fetch!(@services, name)
end
