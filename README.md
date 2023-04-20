# SpaceEx

SpaceEx is an Elixir client library for [kRPC](https://krpc.github.io/krpc/).

kRPC is a mod for [Kerbal Space Program](https://kerbalspaceprogram.com/), the rocket simulation game.

With kRPC, you can control your rocket using external scripts.  With SpaceEx, you can write those external scripts in [Elixir](https://elixir-lang.org/), and enjoy all the wonderful features of the Elixir language and the Erlang VM.

[![Build Status](https://travis-ci.org/wisq/space_ex.svg?branch=master)](https://travis-ci.org/wisq/space_ex)
[![Hex.pm Version](http://img.shields.io/hexpm/v/space_ex.svg?style=flat)](https://hex.pm/packages/space_ex)

## Installation

SpaceEx is [available on hex.pm](https://hex.pm/packages/space_ex).

If you haven't already, start a project with `mix new`.

Then, add `space_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:space_ex, "~> 0.8.0"}
  ]
end
```

Run `mix deps.get` to pull SpaceEx into your project, and you're good to go.

## Usage

```elixir
# If your kRPC is on the same machine:
conn = SpaceEx.Connection.connect!()
# If it's on a different one:
# conn = SpaceEx.Connection.connect!(host: "1.2.3.4")

vessel = SpaceEx.SpaceCenter.active_vessel(conn)
control = SpaceEx.SpaceCenter.Vessel.control(vessel)

SpaceEx.KRPC.set_paused(conn, false)

IO.puts("Burning for 1 second ...")
SpaceEx.SpaceCenter.Control.set_throttle(control, 1.0)
Process.sleep(1_000)
SpaceEx.SpaceCenter.Control.set_throttle(control, 0.0)
IO.puts("Burn complete.")

SpaceEx.KRPC.set_paused(conn, true)
```

This will connect to your kRPC game, unpause it if needed, burn the engines for one second, and then pause it again.

More examples can be found in the [examples directory](https://github.com/wisq/space_ex/tree/master/examples).

Although this library is very new, the API has mostly stabilised at this point, and I expect to release v1.0.0 within the next few days.  For a list of what's planned, see the [to-do list](https://github.com/wisq/space_ex/blob/master/TODO.md).

## Documentation

Full documentation can be found at [https://hexdocs.pm/space_ex](https://hexdocs.pm/space_ex).

## Legal stuff

Copyright © 2018, Adrian Irving-Beer.

SpaceEx is released under the [Apache 2 License](https://github.com/wisq/space_ex/blob/master/LICENSE) and is provided with **no warranty**.  But, let's face it — if anything goes wrong, the worst that can likely happen is that your rocket crashes and Jeb dies.

SpaceEx is in no way associated with the launching of real rockets, and has no affiliations with any companies that do real rocketry.
