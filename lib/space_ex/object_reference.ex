defmodule SpaceEx.ObjectReference do
  @enforce_keys [:id, :class]
  defstruct(
    id: nil,
    class: nil,
    conn: nil
  )
end
