defmodule SpaceEx.ProcedureCall do
  @moduledoc """
  Represents a remote procedure call, for streams and expressions.

  You can create a ProcedureCall by passing a regular SpaceEx call into the
  `create/1` macro.
  """

  @enforce_keys [:conn, :service, :procedure, :args]
  defstruct(
    conn: nil,
    service: nil,
    procedure: nil,
    args: [],
    return_type: nil
  )

  @doc """
  Creates a ProcedureCall structure based on an actual procedure call.

  You can wrap any normal API function call in this, and it will parse that
  into a format suitable for using in streams, expressions, etc.  For example:

  ```elixir
  require SpaceEx.ProcedureCall

  call1 = SpaceEx.ProcedureCall.create(SpaceEx.SpaceCenter.ut(conn))
  # You can also use pipelining:
  call2 =
    SpaceEx.SpaceCenter.Flight.mean_altitude(flight)
    |> SpaceEx.ProcedureCall.create()
  ```

  `create(Mod.func(args))` is equivalent to calling the internal function
  `Mod.rpc_func(args)`.
  """

  defmacro create({{:., _, [module, func]}, _, args}) do
    quote do
      unquote(module).unquote(:"rpc_#{func}")(unquote_splicing(args))
    end
  end
end
