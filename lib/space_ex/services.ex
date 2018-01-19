require SpaceEx.Gen

SpaceEx.API.service_names()
|> List.delete("KRPC")
|> Enum.each(&SpaceEx.Gen.generate_service(&1))
