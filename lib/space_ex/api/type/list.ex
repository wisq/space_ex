defmodule SpaceEx.API.Type.List do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(subtype: nil)

  def parse("LIST", [subtype]) do
    %Type.List{subtype: Type.parse(subtype)}
  end
end
