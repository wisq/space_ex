defmodule SpaceEx.Procedure do
  @enforce_keys [:module, :function, :rpc_service, :rpc_method, :rpc_args]
  defstruct(
    module: nil,
    function: nil,
    rpc_service: nil,
    rpc_method: nil,
    rpc_args: [],
  )

  defmacro call({{:., _, [{:__aliases__, _, mod_parts}, func]}, _, args}) do
    quote do
      module   = Module.concat(unquote(mod_parts))
      function = unquote(func)
      [_conn | args] = unquote(args)

      rpc_service = module.rpc_service_name()
      rpc_method  = module.rpc_method_name(function)
      rpc_args    = module.rpc_encode_arguments(function, args)

      %SpaceEx.Procedure{
        module: module,
        function: function,
        rpc_service: rpc_service,
        rpc_method: rpc_method,
        rpc_args: rpc_args,
      }
    end
  end
end
