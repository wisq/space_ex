defmodule SpaceEx.Connection do
  use GenServer
  alias SpaceEx.Protobufs.{
    ConnectionRequest,
    ConnectionResponse,
    ProcedureCall,
    Argument,
    Request,
    Response,
  }

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

    {:ok, pid} = GenServer.start_link(__MODULE__, sock)
    pid
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

  def call_rpc(pid, service, procedure, args \\ []) do
    args =
      Enum.with_index(args)
      |> Enum.map(fn {arg, index} ->
        Argument.new(position: index, value: arg)
      end)

    call = ProcedureCall.new(
      service: service,
      procedure: procedure,
      arguments: args,
    ) |> IO.inspect

    request =
      Request.new(calls: [call])
      |> Request.encode

    response =
      GenServer.call(pid, {:rpc, request})
      |> Response.decode
      |> IO.inspect

    if response.error do
      {:error, response.error}
    else
      [call_reply] = response.results

      if call_reply.error do
        {:error, call_reply.error}
      else
        {:ok, call_reply.value}
      end
    end
  end

  def handle_call({:rpc, bytes}, _, sock) do
    send_message(sock, bytes)
    {:reply, recv_message(sock), sock}
  end
end
