defmodule SpaceEx.API.Type.ProcedureCall do
  alias SpaceEx.API.Type

  @moduledoc false

  defstruct []

  def parse("PROCEDURE_CALL", %{}) do
    %Type.ProcedureCall{}
  end
end
