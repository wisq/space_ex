defmodule SpaceEx.Test.MockStreamConnection do
  use GenServer

  import ExUnit.Callbacks

  def start do
    {:ok, pid} = start_supervised(__MODULE__, restart: :temporary)
    pid
  end

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, nil}
  end

  # TODO: calls to
  #   * allow Streams to register
  #   * receive fake stream values and dispatch them to Streams
  #   * Maybe we can just import most of StreamConnection?
end
