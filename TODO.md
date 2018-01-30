# To-do list

## Lazy streams and events

This needs some more investigation — I need to look into precisely what other libraries do with their streams and events — but I believe the standard is *not* to start the streams/events right away.  Rather, they wait for the first `get` / `wait` / etc. and then start the stream if it's not started already.

This should be relatively easy to implement — change the `start` default to `false` (or remove it entirely?), add a `started` boolean to `SpaceEx.Stream.State`, change the `start` function to a `GenServer.call`, and have auto-starting behaviour (probably `defp ensure_started`) on `get` etc.  Streams already know about `conn`, so they can issue the call.

It will also have the advantage that users can't accidentally try to `get` a non-started stream and block for a long time because they forgot to start it.
