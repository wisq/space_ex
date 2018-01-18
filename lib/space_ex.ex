defmodule SpaceEx do
  @moduledoc """
    SpaceEx is an Elixir client library for [kRPC](https://krpc.github.io/krpc/).

    kRPC is a mod for [Kerbal Space Program](https://kerbalspaceprogram.com/), the rocket simulation game.

    With kRPC, you can control your rocket using external scripts.  With SpaceEx, you can write those external scripts in Elixir, and enjoy all the wonderful features of the Elixir language and the Erlang VM.

## Usage

    ```elixir
    # If your kRPC is on the same machine:
    conn = SpaceEx.Connection.connect!
    # If it's on a different one:
    #conn = SpaceEx.Connection.connect!(host: "1.2.3.4")

    vessel  = SpaceEx.SpaceCenter.active_vessel(conn)
    control = SpaceEx.SpaceCenter.Vessel.control(conn, vessel)

    SpaceEx.KRPC.set_paused(conn, false)

    IO.puts("Burning for 1 second ...")
    SpaceEx.SpaceCenter.Control.set_throttle(conn, control, 1.0)
    Process.sleep(1_000)
    SpaceEx.SpaceCenter.Control.set_throttle(conn, control, 0.0)
    IO.puts("Burn complete.")

    SpaceEx.KRPC.set_paused(conn, true)
    ```

    This will connect to your kRPC game, unpause it if needed, burn the engines for one second, and then pause it again.

    More examples can be found in the [examples directory](https://github.com/wisq/space_ex/tree/master/examples).
  """
end
