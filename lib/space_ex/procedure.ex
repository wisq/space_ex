defmodule SpaceEx.Procedure do
  @moduledoc """
  Represents a remote procedure call, for streams and expressions.

  Normally created using the `create/4` function or the `call/1` macro.
  """

  @enforce_keys [:module, :function, :conn, :rpc_service, :rpc_method, :rpc_args]
  defstruct(
    module: nil,
    function: nil,
    conn: nil,
    rpc_service: nil,
    rpc_method: nil,
    rpc_args: [],
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
    rpc_service = module.rpc_service_name()
    rpc_method  = module.rpc_method_name(function)
    rpc_args    = module.rpc_encode_arguments(function, args)

    %SpaceEx.Procedure{
      module: module,
      function: function,
      conn: conn,
      rpc_service: rpc_service,
      rpc_method: rpc_method,
      rpc_args: rpc_args,
    }
  end

  @doc """
  Creates a procedure structure based on an actual procedure call.

  You can wrap any normal API function call in this, and it will parse that
  into a format suitable for using in streams, expressions, etc.  For example:

  ```elixir
  require SpaceEx.Procedure

  call1 = SpaceEx.Procedure.create(SpaceEx.SpaceCenter.get_ut(conn))
  # You can also use pipelining:
  call2 =
    SpaceEx.SpaceCenter.Flight.get_mean_altitude(conn, flight)
    |> SpaceEx.Procedure.create
  ```

  `SpaceEx.Procedure.create(Mod.func(conn, args))` is equivalent to calling
  `SpaceEx.Procedure.new(conn, Mod, :func, args)`.
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
