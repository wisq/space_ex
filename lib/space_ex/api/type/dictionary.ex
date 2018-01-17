defmodule SpaceEx.API.Type.Dictionary do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct(
    key_type: nil,
    value_type: nil,
  )

  def parse("DICTIONARY", [key_type, value_type]) do
    %Type.Dictionary{
      key_type: Type.parse(key_type),
      value_type: Type.parse(value_type),
    }
  end
end
