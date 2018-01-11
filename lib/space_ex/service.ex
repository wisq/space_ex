defmodule SpaceEx.Service do
  defmacro __using__(opts) do
    quote do
      import SpaceEx.Service
      define_from_service_json(unquote(opts)[:from], unquote(opts)[:name] || module_basename(__MODULE__))
    end
  end

  def module_basename(mod) do
    Module.split(mod)
    |> List.last
  end

  defmacro define_from_service_json(json_file, service_name) do
    quote do
      json =
        File.read!(unquote(json_file))
        |> Poison.decode!
        |> Map.fetch!(unquote(service_name))

      json
      |> Map.fetch!("procedures")
      |> Enum.map(&define_service_procedure(unquote(service_name), &1))
    end
  end

  defmacro define_service_procedure(service_name, json) do
    quote bind_quoted: [
      service_name: service_name,
      json: json,
    ] do
      {rpc_name, opts} = json
      fn_name = to_snake_case(rpc_name) |> String.to_atom
      fn_args =
        Map.fetch!(opts, "parameters")
        |> Enum.map(fn param ->
          Map.fetch!(param, "name")
          |> String.to_atom
          |> Macro.var(__MODULE__)
        end)

      @doc Map.fetch!(opts, "documentation")
      def unquote(fn_name)(conn, unquote_splicing(fn_args)) do
        SpaceEx.Connection.call_rpc(conn, unquote(service_name), unquote(rpc_name))
      end
    end
  end

  @regex_multi_uppercase ~r'([A-Z]+)([A-Z][a-z0-9])'
  @regex_single_uppercase ~r'([a-z0-9])([A-Z])'
  @regex_underscores ~r'(.)_'

  def to_snake_case(name) do
    name
    #|> regex_replace(@regex_underscores, "\\1__")
    |> regex_replace(@regex_single_uppercase, "\\1_\\2")
    |> regex_replace(@regex_multi_uppercase, "\\1_\\2")
    |> String.downcase
  end

  defp regex_replace(from, regex, to), do: Regex.replace(regex, from, to)
end
