defmodule SpaceEx.Gen do
  alias SpaceEx.API
  alias SpaceEx.Util

  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @service_name opts[:name] || SpaceEx.Util.module_basename(__MODULE__)
      @service SpaceEx.API.service_data(@service_name)
      @before_compile SpaceEx.Gen
    end
  end

  defmacro generate_service(name) do
    quote bind_quoted: [name: name] do
      defmodule Module.concat(SpaceEx, name) do
        use SpaceEx.Gen, name: name
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @moduledoc SpaceEx.Doc.service(@service)

      @doc false
      def rpc_service_name(), do: @service.name

      @service.enumerations
      |> Enum.each(&SpaceEx.Gen.define_enumeration/1)

      @service.classes
      |> Enum.each(&SpaceEx.Gen.define_class(@service, &1))

      @service.procedures
      |> Enum.each(&SpaceEx.Gen.define_procedure(@service, &1))
    end
  end

  defmacro define_enumeration(enum) do
    quote bind_quoted: [enum: enum] do
      defmodule Module.concat(__MODULE__, enum.name) do
        @moduledoc SpaceEx.Doc.enumeration(enum)

        Enum.each(enum.values, &SpaceEx.Gen.define_enumeration_value/1)
      end
    end
  end

  defmacro define_enumeration_value(enum_value) do
    quote bind_quoted: [enum_value: enum_value] do
      atom = enum_value.atom
      wire = SpaceEx.Types.encode_enumeration_value(enum_value.value)

      # Converts a raw wire value to a named atom.
      @doc false
      def wire_to_atom(unquote(wire)), do: unquote(atom)

      # Converts a named atom to a raw wire value.
      @doc false
      def atom_to_wire(unquote(atom)), do: unquote(wire)

      @doc SpaceEx.Doc.enumeration_value(enum_value)
      def unquote(atom)(), do: unquote(atom)
    end
  end

  defmacro define_class(service, class) do
    quote bind_quoted: [
            service: service,
            class: class
          ] do
      defmodule Module.concat(__MODULE__, class.name) do
        @moduledoc SpaceEx.Doc.class(class)

        @doc false
        def rpc_service_name(), do: unquote(service.name)

        class.procedures
        |> Enum.each(&SpaceEx.Gen.define_procedure(service, &1))
      end
    end
  end

  defmacro define_procedure(service, procedure) do
    quote bind_quoted: [
            service: service,
            procedure: procedure
          ] do
      service_name = service.name
      rpc_name = procedure.name

      fn_name = procedure.fn_name

      conn_var = Macro.var(:conn, __MODULE__)
      {def_args, arg_vars, arg_encode_ast} = SpaceEx.Gen.args_builder(procedure, conn_var)

      arg_types = Enum.map(procedure.parameters, fn p -> p.type end) |> Macro.escape()
      return_type = procedure.return_type |> Macro.escape()

      @doc false
      def rpc_procedure(unquote(fn_name)), do: unquote(procedure |> Macro.escape())

      @doc SpaceEx.Doc.procedure(procedure)
      def unquote(fn_name)(unquote_splicing(def_args)) do
        unquote_splicing(arg_encode_ast)

        SpaceEx.Connection.call_rpc!(
          unquote(conn_var),
          unquote(service_name),
          unquote(rpc_name),
          unquote(arg_vars)
        )
        |> SpaceEx.Gen.decode_return(unquote(return_type), unquote(conn_var))
      end
    end
  end

  def args_builder(procedure, conn_var) do
    {mandatory, optional} = Enum.split_with(procedure.parameters, fn p -> is_nil(p.default) end)

    is_method =
      Enum.any?(mandatory, fn
        %API.Procedure.Parameter{name: "this", index: 0} -> true
        _ -> false
      end)

    build_args_with_conn(mandatory, optional, conn_var, is_method: is_method)
  end

  # Not a method: Add `conn` to the start of the function args list.
  defp build_args_with_conn(mandatory, optional, conn_var, is_method: false) do
    {def_args, arg_vars, arg_encode_ast} = build_args_for_params(mandatory, optional)

    def_args = [conn_var | def_args]

    {def_args, arg_vars, arg_encode_ast}
  end

  # Is an object method: Extract `conn` from `this.conn`.
  defp build_args_with_conn(mandatory, optional, conn_var, is_method: true) do
    {def_args, arg_vars, arg_encode_ast} = build_args_for_params(mandatory, optional)

    extract_conn = quote do: unquote(conn_var) = this.conn
    arg_encode_ast = [extract_conn | arg_encode_ast]

    {def_args, arg_vars, arg_encode_ast}
  end

  # No optional params: Just build positional params.
  defp build_args_for_params(mandatory, []) do
    arg_vars = variables_for_params(mandatory)

    arg_encode_ast =
      Enum.zip(mandatory, arg_vars)
      |> Enum.map(fn {param, var} ->
        type = param.type |> Macro.escape()

        quote do
          unquote(var) = SpaceEx.Types.encode(unquote(var), unquote(type))
        end
      end)

    {arg_vars, arg_vars, arg_encode_ast}
  end

  # Optional params:
  #
  # * Add `opts \\ []` to function definition.
  # * Create a variable for each param, and encode the param
  #   into it (if supplied), or use the default.
  # * Complain if we get any opts that we don't recognise.
  defp build_args_for_params(mandatory, optional) do
    {def_args, arg_vars, arg_encode_ast} = build_args_for_params(mandatory, [])

    new_vars = variables_for_params(optional)
    atoms = atoms_for_params(optional)

    new_encodes =
      Enum.zip([optional, new_vars, atoms])
      |> Enum.map(fn {param, var, atom} ->
        type = param.type |> Macro.escape()

        quote do
          unquote(var) =
            if Keyword.has_key?(opts, unquote(atom)) do
              SpaceEx.Types.encode(opts[unquote(atom)], unquote(type))
            else
              unquote(param.default)
            end
        end
      end)

    reject_unknown =
      quote do
        case Keyword.keys(opts) |> Enum.reject(fn key -> key in unquote(atoms) end) do
          [] ->
            :ok

          bad_keys ->
            bad_keys = Enum.map(bad_keys, &inspect/1) |> Enum.join(", ")
            raise "Unknown parameter(s): #{bad_keys}"
        end
      end

    def_args = def_args ++ [quote(do: opts \\ [])]
    arg_vars = arg_vars ++ new_vars
    arg_encode_ast = arg_encode_ast ++ new_encodes ++ [reject_unknown]

    {def_args, arg_vars, arg_encode_ast}
  end

  defp variables_for_params(params) do
    atoms_for_params(params)
    |> Enum.map(&Macro.var(&1, __MODULE__))
  end

  defp atoms_for_params(params) do
    Enum.map(params, fn p ->
      Util.to_snake_case(p.name)
      |> String.to_atom()
    end)
  end

  # FIXME: need to move this out to a better module
  def encode_args([], []), do: []

  def encode_args([arg | args], [type | types]) do
    value = SpaceEx.Types.encode(arg, type)
    [value | encode_args(args, types)]
  end

  # FIXME: need to move this out to a better module
  def decode_return("", nil, _conn), do: :ok

  def decode_return(value, type, conn) do
    SpaceEx.Types.decode(value, type, conn)
  end
end
