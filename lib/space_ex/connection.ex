defmodule SpaceEx.Connection do
  alias SpaceEx.Protobufs.{ConnectionRequest, ConnectionResponse} 

  def connect!(host, port) do
    sock = Socket.TCP.connect!(host, port, packet: :raw)

    request =
      ConnectionRequest.new(type: :RPC, client_name: "test-client-1")
      |> ConnectionRequest.encode

    send_message(sock, request)

    response =
      recv_message(sock)
      |> ConnectionResponse.decode

    case response.status do
      :OK -> sock
      _ -> raise "kRPC connection failed: #{inspect response.message}"
    end
  end

  def send_message(sock, message) do
    size =
      byte_size(message)
      |> :gpb.encode_varint

    Socket.Stream.send!(sock, size <> message)
  end

  def recv_message(sock, buffer \\ <<>>) do
    case Socket.Stream.recv!(sock, 1) do
      <<1 :: size(1), _ :: bitstring>> = byte ->
        # high bit set, varint incomplete
        recv_message(sock, buffer <> byte)

      <<0 :: size(1), _ :: bitstring>> = byte ->
        {size, ""} = :gpb.decode_varint(buffer <> byte)
        Socket.Stream.recv!(sock, size)

      nil -> raise "kRPC connection closed"
    end
  end
end
