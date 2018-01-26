defmodule SpaceEx.API.Type.Class do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(name: nil, module: nil)

  def parse("CLASS", %{"name" => name, "service" => service}) do
    module = Module.concat([SpaceEx, service, name])
    %Type.Class{name: name, module: module}
  end
end
