defmodule SpaceEx.Procedure do
  @moduledoc """
  Represents a remote procedure call, for streams and expressions.

  Normally created using the `new/4` function or the `create/1` macro.
  """

  @enforce_keys [:conn, :service, :procedure, :args]
  defstruct(
    conn: nil,
    service: nil,
    procedure: nil,
    args: [],
    return_type: nil,
  )

  @doc """
  Creates a procedure structure, representing a kRPC procedure call.

  * `conn` — a `SpaceEx.Connection`
  * `module` — a SpaceEx kRPC module, e.g. `SpaceEx.SpaceCenter.Vessel`
  * `function` — the function name, as an atom, e.g. `:get_max_thrust`
  * `args` — the arguments as an array (if any)

  Any arguments will be immediately encoded, so most errors related to argument
  data (e.g. incorrect type) will be detected immediately.
  """

  def new(conn, module, function, args \\ []) do
    service_name = module.rpc_service_name()
    proc = module.rpc_procedure(function)

    arg_types = Enum.map(proc.parameters, fn p -> p.type end)
    args = SpaceEx.Gen.encode_args(args, arg_types)

    %SpaceEx.Procedure{
      conn: conn,
      service: service_name,
      procedure: proc.name,
      args: args,
      return_type: proc.return_type,
    }
  end

  @doc """
  Creates a procedure structure based on an actual procedure call.

  You can wrap any normal API function call in this, and it will parse that
  into a format suitable for using in streams, expressions, etc.  For example:

  ```elixir
  require SpaceEx.Procedure

  call1 = SpaceEx.Procedure.create(SpaceEx.SpaceCenter.ut(conn))
  # You can also use pipelining:
  call2 =
    SpaceEx.SpaceCenter.Flight.mean_altitude(conn, flight)
    |> SpaceEx.Procedure.create
  ```

  `create(Mod.func(conn, args))` is equivalent to calling
  `new(conn, Mod, :func, [args])`.
  """

  defmacro create({{:., _, [module, func]}, _, args}) do
    quote bind_quoted: [
      module: module,
      function: func,
      macro_args: args
    ] do
      [conn | args] = macro_args

      SpaceEx.Procedure.new(conn, module, function, args)
    end
  end
end
