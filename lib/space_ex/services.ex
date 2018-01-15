require SpaceEx.Gen

SpaceEx.API.service_names
|> Enum.each(&SpaceEx.Gen.generate_service(&1))
