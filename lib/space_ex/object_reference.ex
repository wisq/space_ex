defmodule SpaceEx.ObjectReference do
  @moduledoc false

  @enforce_keys [:id, :class]
  defstruct(
    id: nil,
    class: nil,
    conn: nil
  )
end
