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

  def recv_message(sock, received \\ <<>>) do
    byte = Socket.Stream.recv!(sock, 1)
    buffer = received <> byte

    case try_decode_varint(buffer) do
      {:ok, size} -> Socket.Stream.recv!(sock, size)
      {:error, _} -> recv_message(sock, buffer)
    end
  end

  def try_decode_varint(bytes) do
    try do
      {int, ""} = :gpb.decode_varint(bytes)
      {:ok, int}
    rescue
      FunctionClauseError -> {:error, :incomplete}
    end
  end
end
