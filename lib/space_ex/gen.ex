defmodule SpaceEx.Gen do
  alias SpaceEx.Util

  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @service_name opts[:name] || SpaceEx.Util.module_basename(__MODULE__)
      @service SpaceEx.API.service_data(@service_name)
      @service_overrides opts[:overrides] || %{}
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
    quote do
      @moduledoc SpaceEx.Doc.service(@service)

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

        @service_overrides %{}

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
      value_var = Macro.var(:value, __MODULE__)

      {def_args, arg_vars, arg_encode_ast} = SpaceEx.Gen.args_builder(procedure, conn_var)
      guard_ast = SpaceEx.Gen.guard_clause(def_args)

      return_type = procedure.return_type |> Macro.escape()
      return_decode_ast = SpaceEx.Gen.return_decoder(return_type, value_var, conn_var)

      overrides = Map.get(@service_overrides, fn_name, [])

      if :nodoc in overrides do
        @doc false
      else
        @doc SpaceEx.Doc.procedure(procedure)
      end

      def unquote(fn_name)(unquote_splicing(def_args)) when unquote(guard_ast) do
        unquote_splicing(arg_encode_ast)

        unquote(value_var) =
          SpaceEx.Connection.call_rpc!(
            unquote(conn_var),
            unquote(service_name),
            unquote(rpc_name),
            unquote(arg_vars)
          )

        unquote(return_decode_ast)
      end

      @doc false
      def unquote(:"rpc_#{fn_name}")(unquote_splicing(def_args)) when unquote(guard_ast) do
        unquote_splicing(arg_encode_ast)

        %SpaceEx.Procedure{
          conn: unquote(conn_var),
          service: unquote(service_name),
          procedure: unquote(rpc_name),
          args: unquote(arg_vars),
          return_type: unquote(return_type)
        }
      end
    end
  end

  #
  # Returns {def_args, arg_vars, arg_encode_ast}
  #
  # def_args:
  #   One variable per FUNCTION argument, in `def` format (including `\\`).
  #   These will be used via `def x(def_args)` and `def rpc_x(def_args)`.
  #
  # arg_vars:
  #   One variable per RPC PROCEDURE argument,
  #   These will be the `args` sent to `Connection.call_rpc`.
  #
  # arg_encode_ast:
  #   AST to convert `def_args` into `arg_vars`.
  #   Will call `Type.encode` as needed.
  #
  def args_builder(procedure, conn_var) do
    build_positional_args(procedure.positional_params)
    |> add_optional_args(procedure.optional_params)
    |> add_conn_var(conn_var, procedure.is_object_method)
  end

  # Build {def_args, arg_vars, arg_encode_ast} for the mandatory, positional vars.
  defp build_positional_args(params) do
    arg_vars = variables_for_params(params)

    arg_encode_ast =
      Enum.zip(params, arg_vars)
      |> Enum.map(fn {param, var} ->
        type = param.type |> Macro.escape()

        quote do
          unquote(var) = SpaceEx.Types.encode(unquote(var), unquote(type))
        end
      end)

    {arg_vars, arg_vars, arg_encode_ast}
  end

  # Build {def_args, arg_vars, arg_encode_ast} for the optional (`opts \\ []`) vars.

  # If there are no optional args, then this is a noop.
  defp add_optional_args(details, []), do: details

  # * Add `opts \\ []` to function definition.
  # * Create a variable for each param, and encode the param
  #   into it (if supplied), or use the default.
  # * Complain if we get any opts that we don't recognise.
  defp add_optional_args({def_args, arg_vars, arg_encode_ast}, params) do
    new_vars = variables_for_params(params)
    atoms = atoms_for_params(params)

    new_encodes =
      Enum.zip([params, new_vars, atoms])
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

    {
      def_args ++ [quote(do: opts \\ [])],
      arg_vars ++ new_vars,
      arg_encode_ast ++ new_encodes ++ [reject_unknown]
    }
  end

  # Derive the `conn` var -- either AS the first arg, or VIA the first arg.

  # Not a method: Add `conn` to the start of the function args list.
  defp add_conn_var({def_args, arg_vars, arg_encode_ast}, conn_var, false) do
    {
      [conn_var | def_args],
      arg_vars,
      arg_encode_ast
    }
  end

  # Is an object method: Extract `conn` from `this.conn`.
  defp add_conn_var({def_args, arg_vars, arg_encode_ast}, conn_var, true) do
    extract_conn = quote do: unquote(conn_var) = this.conn

    {
      def_args,
      arg_vars,
      [extract_conn | arg_encode_ast]
    }
  end

  # Create a list of variables for a list of API.Procedure.Parameters.
  defp variables_for_params(params) do
    atoms_for_params(params)
    |> Enum.map(&Macro.var(&1, __MODULE__))
  end

  # Create a list of snake_case atoms for a list of API.Procedure.Parameters.
  defp atoms_for_params(params) do
    Enum.map(params, fn p ->
      Util.to_snake_case(p.name)
      |> String.to_atom()
    end)
  end

  # Returns AST for decoding the return value from `call_rpc`.
  #
  # No type: Check that we got zero bytes, then just return `:ok`.
  def return_decoder(nil, value_var, _conn_var) do
    quote do
      <<>> = unquote(value_var)
      :ok
    end
  end

  # A return type: Decode it.
  def return_decoder(type, value_var, conn_var) do
    quote do
      SpaceEx.Types.decode(unquote(value_var), unquote(type), unquote(conn_var))
    end
  end

  # We add a guard to make sure users don't get confused
  # and do e.g. `Vessel.flight(vessel, ref_frame)`
  # when they should do `Vessel.flight(vessel, reference_frame: ref_frame)`.
  #
  # If there's an `opts \\ []` in our `def_args`, then guard on it being a list.
  #
  # Otherwise, return a `true` (noop) guard.

  def guard_clause(args) do
    case List.last(args) do
      # Search for `opts \\ []` and extract `opts` variable.
      {:\\, _, [{:opts, _, _} = opts_var, []]} ->
        quote do: is_list(unquote(opts_var))

      _ ->
        quote do: true
    end
  end
end
