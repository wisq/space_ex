defmodule SpaceEx.SpaceCenter do
  use SpaceEx.Service, from: Path.expand("api/KRPC.SpaceCenter.json", __DIR__)
end
