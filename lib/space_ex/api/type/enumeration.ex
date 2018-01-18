defmodule SpaceEx.API.Type.Enumeration do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(module: nil)

  def parse("ENUMERATION", %{"service" => service, "name" => name}) do
    %Type.Enumeration{
      module: Module.concat([SpaceEx, service, name])
    }
  end
end
