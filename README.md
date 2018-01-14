# SpaceEx

SpaceEx is an Elixir client library for [kRPC](https://krpc.github.io/krpc/).

kRPC is a mod for [Kerbal Space Program](https://kerbalspaceprogram.com/), the rocket simulation game.

With kRPC, you can control your rocket using external scripts.  With SpaceEx, you can write those external scripts in [Elixir](https://elixir-lang.org/), and enjoy all the wonderful features of the Elixir language and the Erlang VM.

## Installation

If you haven't already, start a project with `mix new`.

Then, add `space_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:space_ex, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to pull SpaceEx into your project, and you're good to go.

## Documentation

Full documentation can be found at [https://hexdocs.pm/space_ex](https://hexdocs.pm/space_ex).

## Legal stuff

Copyright © 2018, Adrian Irving-Beer.

SpaceEx is released under the [Apache 2 License](LICENSE) and is provided with **no warranty**.  But, let's face it — if anything goes wrong, the worst that can likely happen is that your rocket crashes and Jeb dies.

SpaceEx is in no way associated with the launching of real rockets, and has no affiliations with any companies that do real rocketry, as kickass as they (and their CEO) may be.
