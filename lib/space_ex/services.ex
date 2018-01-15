require SpaceEx.Gen

SpaceEx.API.service_names
|> Enum.each(fn name ->
  module = Module.concat(SpaceEx, name)

  case Code.ensure_compiled(module) do
    {:module, ^module} -> :ok
    {:error, :nofile} -> SpaceEx.Gen.generate_service(name)
  end
end)
