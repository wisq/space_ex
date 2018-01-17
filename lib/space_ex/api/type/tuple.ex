defmodule SpaceEx.API.Type.Tuple do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(subtypes: nil)

  def parse("TUPLE", subtypes) do
    %Type.Tuple{
      subtypes: Enum.map(subtypes, &Type.parse/1)
    }
  end
end
