defmodule SpaceEx.Types do
  @moduledoc false

  defdelegate decode(bytes, type), to: SpaceEx.Types.Decoders
  defdelegate encode(bytes, type), to: SpaceEx.Types.Encoders
end
