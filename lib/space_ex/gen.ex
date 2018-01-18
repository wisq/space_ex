defmodule SpaceEx.Gen do
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

      fn_args =
        Enum.map(procedure.parameters, fn p ->
          String.to_atom(p.name)
          |> Macro.var(__MODULE__)
        end)

      arg_types = Enum.map(procedure.parameters, fn p -> p.type end) |> Macro.escape()
      return_type = procedure.return_type |> Macro.escape()

      @doc false
      def rpc_procedure(unquote(fn_name)), do: unquote(procedure |> Macro.escape())

      @doc SpaceEx.Doc.procedure(procedure)
      def unquote(fn_name)(conn, unquote_splicing(fn_args)) do
        args = SpaceEx.Gen.encode_args(unquote(fn_args), unquote(arg_types))

        SpaceEx.Connection.call_rpc!(conn, unquote(service_name), unquote(rpc_name), args)
        |> SpaceEx.Gen.decode_return(unquote(return_type))
      end
    end
  end

  # FIXME: need to move this out to a better module
  def encode_args([], []), do: []

  def encode_args([arg | args], [type | types]) do
    value = SpaceEx.Types.encode(arg, type)
    [value | encode_args(args, types)]
  end

  # FIXME: need to move this out to a better module
  def decode_return("", nil), do: :ok

  def decode_return(value, type) do
    SpaceEx.Types.decode(value, type)
  end
end
