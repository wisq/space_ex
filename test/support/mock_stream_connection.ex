defmodule SpaceEx.Test.MockStreamConnection do
  use GenServer
  import ExUnit.Callbacks

  alias SpaceEx.StreamConnection

  def start do
    {:ok, pid} = start_supervised(__MODULE__, restart: :temporary)
    pid
  end

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, %StreamConnection.State{socket: nil}}
  end

  def handle_call({:whereis, _} = call, from, state) do
    StreamConnection.handle_call(call, from, state)
  end

  def handle_call({:register, _, _} = call, from, state) do
    StreamConnection.handle_call(call, from, state)
  end

  # TODO: calls to
  #   * allow Streams to register
  #   * receive fake stream values and dispatch them to Streams
  #   * Maybe we can just import most of StreamConnection?
end
