defmodule SpaceEx.Util.Connection do
  @moduledoc false

  def send_message(message, socket) do
    size =
      byte_size(message)
      |> :gpb.encode_varint()

    Socket.Stream.send!(socket, size <> message)
  end

  # Only called during initialisation.
  # After that, the socket is in active mode,
  # and all replies come via handle_info messages.
  def recv_message(socket, buffer \\ <<>>) do
    case Socket.Stream.recv!(socket, 1) do
      <<1::size(1), _::bitstring>> = byte ->
        # high bit set, varint incomplete
        recv_message(socket, buffer <> byte)

      <<0::size(1), _::bitstring>> = byte ->
        {size, ""} = :gpb.decode_varint(buffer <> byte)
        Socket.Stream.recv!(socket, size)

      nil ->
        raise "kRPC connection closed"
    end
  end

  def extract_message(buffer) do
    case safe_decode_varint(buffer) do
      {size, leftover} ->
        case leftover do
          <<message::bytes-size(size), new_buffer::binary>> ->
            {:ok, message, new_buffer}

          _ ->
            {:error, :incomplete}
        end

      nil ->
        {:error, :incomplete}
    end
  end

  defp safe_decode_varint(bytes) do
    if has_varint?(bytes) do
      :gpb.decode_varint(bytes)
    else
      nil
    end
  end

  defp has_varint?(<<>>), do: false
  # high bit unset, varint complete
  defp has_varint?(<<0::size(1), _::bitstring>>), do: true
  # high bit set, varint incomplete
  defp has_varint?(<<1::size(1), _::size(7), rest::bitstring>>), do: has_varint?(rest)
end
