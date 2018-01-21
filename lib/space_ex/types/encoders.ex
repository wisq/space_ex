defmodule SpaceEx.Types.Encoders do
  alias SpaceEx.API.Type
  alias SpaceEx.{Protobufs, ObjectReference}

  @moduledoc false

  def encode(value, %Type.Raw{module: module}) do
    <<_first_byte, rest::bitstring>> =
      module.new(value: value)
      |> module.encode

    rest
  end

  def encode(value, %Type.Protobuf{module: module}) do
    module.encode(value)
  end

  def encode(value, %Type.List{subtype: subtype}) do
    items = Enum.map(value, &encode(&1, subtype))

    Protobufs.List.new(items: items)
    |> Protobufs.List.encode()
  end

  def encode(value, %Type.Set{subtype: subtype}) do
    items = Enum.map(value, &encode(&1, subtype))

    Protobufs.List.new(items: items)
    |> Protobufs.List.encode()
  end

  def encode(value, %Type.Tuple{subtypes: subtypes}) do
    items =
      Tuple.to_list(value)
      |> encode_tuple(subtypes)

    Protobufs.Tuple.new(items: items)
    |> Protobufs.Tuple.encode()
  end

  def encode(%SpaceEx.Procedure{} = proc, %Type.ProcedureCall{}) do
    args =
      Enum.with_index(proc.args)
      |> Enum.map(fn {arg, index} ->
        Protobufs.Argument.new(position: index, value: arg)
      end)

    Protobufs.ProcedureCall.new(
      service: proc.service,
      procedure: proc.procedure,
      arguments: args
    )
    |> Protobufs.ProcedureCall.encode()
  end

  def encode(value, %Type.Enumeration{module: module}) do
    module.atom_to_wire(value)
  end

  def encode(value, %Type.Class{name: class}) do
    %ObjectReference{class: ^class, id: id} = value
    id
  end

  defp encode_tuple([], []), do: []

  defp encode_tuple([item | items], [type | types]) do
    [encode(item, type) | encode_tuple(items, types)]
  end
end
