defmodule SpaceEx.API.Type.Set do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(subtype: nil)

  def parse("SET", [subtype]) do
    %Type.Set{subtype: Type.parse(subtype)}
  end
end
