defmodule SpaceExTest do
  use ExUnit.Case
  doctest SpaceEx

  test "greets the world" do
    assert SpaceEx.hello() == :world
  end
end
