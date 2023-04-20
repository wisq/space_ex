# To-do list

Development stalled out in 2018.  Since then, there's been some notable events:

## KSP 2

Kerbal Space Program 2 was announced in 2019, and hit Early Access in 2023.  At
this point, my interest in KSP1 has mostly fallen away, so development on this
library is 100% on hold at the moment.

I don't know if there will be a kRPC (or equivalent) for KSP2, or what it might
look like.  But I imagine that if/when it happens, this library will likely be
resurrected and ported (or rewritten) to use it.

## GenStage

Elixir released [GenStage](https://github.com/elixir-lang/gen_stage), a much
better way to create an events pipeline.  Technically this was in 2016, but it
took me until much more recently to discover how useful it is.

The entire `SpaceEx.Stream` system could probably be rewritten using this.  I
might still want to put some syntactic sugar on top to keep things clean from a
library user's point of view.  And, of course, the entire future of streams
will depend on what our KSP2 RPC API (if any) looks like.
