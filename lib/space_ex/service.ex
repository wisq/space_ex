defmodule SpaceEx.Service do
  defmacro __using__(opts) do
    quote do
      require SpaceEx.Types

      json_file = unquote(opts)[:from]

      @service_name unquote(opts)[:name] || SpaceEx.Service.module_basename(__MODULE__)
      @service_json (
        File.read!(json_file)
        |> Poison.decode!
        |> Map.fetch!(@service_name)
      )
      @external_resource json_file
      @before_compile SpaceEx.Service
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @service_json
      |> Map.fetch!("enumerations")
      |> Enum.each(&SpaceEx.Service.define_enumeration(@service_name, &1))

      @service_json
      |> SpaceEx.Service.procedures_by_class
      |> Enum.each(fn {class, procedures} ->
        SpaceEx.Service.define_service_module(@service_name, class, procedures)
      end)
    end
  end

  defmacro define_enumeration(service_name, json) do
    quote bind_quoted: [
      service_name: service_name,
      json: json,
    ] do
      {enum_name, opts} = json

      defmodule :"Elixir.SpaceEx.#{service_name}.#{enum_name}" do
        Map.fetch!(opts, "values")
        |> Enum.each(fn %{"name" => name, "value" => value} ->
          SpaceEx.Service.define_enumeration_value(name, value)
        end)
      end
    end
  end

  defmacro define_enumeration_value(name, value) do
    quote bind_quoted: [
      name: name,
      value: value,
    ] do
      name =
        SpaceEx.Service.to_snake_case(name)
        |> String.to_atom
      def atom(unquote(value)), do: unquote(name)
      def value(unquote(name)), do: unquote(value)

      def unquote(name)(), do: unquote(name)
    end
  end

  defmacro define_service_module(service_name, class, procedures) do
    quote bind_quoted: [
      service_name: service_name,
      class: class,
      procedures: procedures,
    ] do
      if class do
        {class_name, _} = class
        service_name = @service_name
        defmodule Module.concat(__MODULE__, String.to_atom(class_name)) do
          Enum.each(procedures, &SpaceEx.Service.define_service_procedure(service_name, class_name, &1))
        end
      else
        Enum.each(procedures, &SpaceEx.Service.define_service_procedure(@service_name, nil, &1))
      end
    end
  end

  defmacro define_service_procedure(service_name, class_name, json) do
    quote bind_quoted: [
      service_name: service_name,
      class_name: class_name,
      json: json,
    ] do
      {rpc_name, opts} = json
      fn_name = SpaceEx.Service.rpc_function_name(rpc_name, class_name)
      {fn_args, arg_encoders} = Map.fetch!(opts, "parameters") |> SpaceEx.Service.args_builder
      return_type = Map.get(opts, "return_type", nil) |> Macro.escape

      @doc Map.fetch!(opts, "documentation")
      def unquote(fn_name)(conn, unquote_splicing(fn_args)) do
        args = SpaceEx.Service.encode_args(unquote(fn_args), unquote(arg_encoders))

        case SpaceEx.Connection.call_rpc(conn, unquote(service_name), unquote(rpc_name), args) do
          {:ok, value} -> {:ok, SpaceEx.Types.decode(value, unquote(return_type))}
          {:error, error} -> {:error, error}
        end
      end

      def unquote(:"#{fn_name}!")(conn, unquote_splicing(fn_args)) do
        case unquote(fn_name)(conn, unquote_splicing(fn_args)) do
          {:ok, value} -> value
          {:error, error} -> raise error.description
        end
      end
    end
  end

  @regex_multi_uppercase ~r'([A-Z]+)([A-Z][a-z0-9])'
  @regex_single_uppercase ~r'([a-z0-9])([A-Z])'
  #@regex_underscores ~r'(.)_'

  def to_snake_case(name) do
    name
    #|> String.replace(@regex_underscores, "\\1__")
    |> String.replace(@regex_single_uppercase, "\\1_\\2")
    |> String.replace(@regex_multi_uppercase, "\\1_\\2")
    |> String.downcase
  end

  def module_basename(mod) do
    Module.split(mod)
    |> List.last
  end

  def procedures_by_class(json) do
    classes = Map.fetch!(json, "classes")
    procedures = Map.fetch!(json, "procedures")

    [nil | Enum.to_list(classes)]
    |> Enum.map(fn class ->
      {class, class_procedures(class, procedures, classes)}
    end)
  end

  # Find procedures without any class.
  def class_procedures(nil, procedures, classes) do
    Enum.reject(procedures, fn {proc_name, _} ->
      Enum.any?(classes, fn {class_name, _} ->
        String.starts_with?(proc_name, "#{class_name}_")
      end)
    end)
  end

  # Find procedures for a particular class.
  def class_procedures({class_name, _}, procedures, _classes) do
    Enum.filter(procedures, fn {proc_name, _} ->
      String.starts_with?(proc_name, "#{class_name}_")
    end)
  end

  def rpc_function_name(rpc_name, nil) do
    to_snake_case(rpc_name)
    |> String.to_atom
  end

  def rpc_function_name(rpc_name, class_name) do
    String.replace(rpc_name, ~r{^#{Regex.escape(class_name)}_}, "")
    |> rpc_function_name(nil)
  end

  def args_builder(params) do
    fn_args =
      Enum.map(params, fn param ->
        Map.fetch!(param, "name")
        |> String.to_atom
        |> Macro.var(__MODULE__)
      end)

    arg_encoders =
      Enum.map(params, fn param ->
        type = Map.fetch!(param, "type") |> Macro.escape

        quote do
          fn arg ->
            SpaceEx.Types.encode(arg, unquote(type))
          end
        end
      end)

    {fn_args, arg_encoders}
  end

  def encode_args([], []), do: []

  def encode_args([arg | args], [encoder | encoders]) do
    [encoder.(arg) | encode_args(args, encoders)]
  end
end
