defmodule SpaceEx.Types do
  def decoder(nil) do
    fn _ -> :ok end
  end

  def decoder(%{"code" => "LIST", "types" => [subtype]}) do
    subdecoder = decoder(subtype)

    fn input ->
      SpaceEx.Protobufs.List.decode(input).items
      |> Enum.map(subdecoder)
    end
  end

  def decoder(%{"code" => "TUPLE", "types" => subtypes}) do
    subdecoders = Enum.map(subtypes, &decoder/1)

    fn input ->
      SpaceEx.Protobufs.Tuple.decode(input).items
      |> map_tuple(subdecoders)
      |> List.to_tuple
    end
  end

  def decoder(%{"code" => code}) do
    IO.puts("unknown type code: #{code}")
    fn x -> x end
  end

  def map_tuple([], []), do: []
  def map_tuple([item | items], [decoder | decoders]),
    do: [decoder.(item) | map_tuple(items, decoders)]
end
