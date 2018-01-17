defmodule SpaceEx.API.Type.Class do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(name: nil)

  def parse("CLASS", %{"name" => name}) do
    %Type.Class{name: name}
  end
end
