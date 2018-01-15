defmodule SpaceEx.Types do
  alias SpaceEx.Types.{Encoders, Decoders}

  @moduledoc false

  defmacro decode(_input, nil) do
    :ok
  end

  defmacro decode(input, {:%{}, _, tuples}) do
    opts = Map.new(tuples)
    code = Map.fetch!(opts, "code") |> String.to_atom
    types = Map.get(opts, "types", nil)

    decoder = Decoders.type_decoder(input, code, opts)

    if post = Decoders.post_decode(code, types, opts) do
      {:"|>", [], [decoder, post]}
    else
      decoder
    end
  end

  defmacro encode(input, {:%{}, _, tuples}) do
    opts = Map.new(tuples)
    code = Map.fetch!(opts, "code") |> String.to_atom

    Encoders.type_encoder(input, code, opts)
  end

  defmacro encode(input, code) when is_atom(code) do
    Encoders.type_encoder(input, code, %{})
  end

  SpaceEx.Protobufs.defs
  |> Enum.map(&elem(&1, 0))
  |> Enum.filter(fn {type, _} -> type == :msg end)
  |> Enum.each(fn {_, module} ->
    type_code =
      module
      |> SpaceEx.Util.module_basename
      |> SpaceEx.Util.to_snake_case
      |> String.upcase
      |> String.to_atom

    def protobuf_module(unquote(type_code)), do: unquote(module)
  end)

  def protobuf_module(_), do: nil
end
