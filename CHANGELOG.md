# Changelog

## v0.8.0

* Reworked `SpaceEx.Stream.subscribe/2`.
  * Now delivers raw, undecoded results.
  * No longer unsubscribes after a single message (unless using `remove` option).
  * Most user code will want to use the new `SpaceEx.Stream.receive_latest/2`; some may want `SpaceEx.Stream.receive_next/2`.
  * **Breaking API change.**  Most existing code will fail quickly due to attempting to subscribe multiple times.
* Added `SpaceEx.Stream.receive_latest/2`.
  * Receives *latest* subscribed result in process mailbox.
  * Safe from mailbox overflow due to skipping older results.
* Added `SpaceEx.Stream.receive_next/2`.
  * Receives *next* subscribed result in process mailbox.
  * Safe from mailbox overflow due to enforcing a maximum message age.

## v0.7.0

### New functionality

* Added `SpaceEx.ExpressionBuilder`, a far easier way to create `SpaceEx.KRPC.Expression` objects.
  * Converted `sub_orbital_flight.exs` to use the new expression builder.
* Added the `start: false` option to `SpaceEx.Event.create/2`.
  * Can be used to create an event but start checking it later.
* Added `SpaceEx.Event.start/1` to manually start an event stream.
* Added `SpaceEx.Event.set_rate/2` to set the polling rate of an event.
* Added `SpaceEx.Stream.subscribe/2` and `SpaceEx.Event.subscribe/2` to allow asynchronous handling of streams and events.

### API changes

* Fixed the `SpaceEx.Connection.connect` and `connect!` to allow zero args again.
* Replaced `SpaceEx.Stream.stream_fn/2` with `SpaceEx.Stream.with_get_fn/1`.
  * `... |> Stream.stream_fn` is now `... |> Stream.stream |> Stream.with_get_fn`
* Removed the `conn` argument from `SpaceEx.Event.create/1`.
  * It can derive `conn` from `expr`.
  * This also allows for expressions to be pipelined in.
* Changed `SpaceEx.Event.wait/2` to use keyword options.
  * Timeout is now `opts[:timeout]`.
  * Added `opts[:remove]`, default `true`.

### Other

* Fixed bugs with `SpaceEx.Stream.set_rate/2` and `SpaceEx.Stream.start/1`.
* Fixed race condition with `SpaceEx.Stream` shutdown.
  * `SpaceEx.KRPC.remove_stream/2` now has a `cast_remove_stream` version to facilitate this.
  * Now potentially easy to add `cast_` versions to other functions.
* Added more tests for `SpaceEx.Stream` and `SpaceEx.Event`.
* Stricter parameter and return type validation for `SpaceEx.Stream` calls.
* API documentation now gives details on every RPC function's return value.
  * This helps users know what constant types to use in Expressions and the ExpressionBuilder.
* Examples split out into their own directories.
  * Multiple versions of each, in progessively more Elixir-y style.

## v0.6.0
 
### User-facing

* Renamed `SpaceEx.Procedure` to `ProcedureCall`.
* Add `SpaceEx.Connection.connect/1`, the Erlang-style version of `connect!`.
* Add `SpaceEx.Connection.close/1`.
* Connection process lifecycle changes:
  * The concept is still the same, but we handle exits (particularly `exit(:normal)`) better.
  * The entire `Connection`, `StreamConnection`, and all active `Stream`s should exit together now, either cleanly or on error.
  * We still link the `Connection` process to the launching process.
* Connections will now handle server disconnects better.
  * They'll still blow up, of course, but with a meaningful message.
* Updated docs:
  * Used absolute URLs, so links work whether on HexDocs or GitHub.
  * Fixed code-quoted HTML entities showing up, e.g. for `SpaceEx.SpaceCenter.launch_vessel/4`.

### Internal

* Add tests for core classes:
  * `Connection`
  * `StreamConnection`
  * `Stream`
  * `Event`
* Add selective mocked tests for API calls:
  * `KRPC`
  * `SpaceCenter`
* Add some missing encoders and decoders.
  * These aren't used in the API, but they offer symmetry, e.g. encoding values we know how to decode and vice versa.
  * Tests added as well.
* Rework parts of `SpaceEx.Gen`.
  * We no longer have to pass `conn_var` and `value_var` around.
  * Only three `var!(x)`s required; the rest are bare.
  * We use `location: :keep` on every `quote`, so stack traces will be more sensible now.
* Added Travis CI testing.
  * We can now guarantee compatibility with Elixir 1.5/1.6, and OTP 18/19/20.

## v0.5.1

* Fixed a bug that was causing **every** function to have an `opts` argument, even if it didn't have any optional args.
* Fixed a crash when a `Connection` tries to terminate because its parent process has exited.  Now it should crash *correctly*. 🙂
* Added some tests.  More to come.

## v0.5.0

Major (and very breaking) overhaul to function arguments.

### Connection references

* Functions that return remote object reference(s) — `SpaceCenter.active_vessel`, `Orbit.body`, etc. — will now return structure(s) containing the reference and the connection it was retrieved via.
* Functions that take a `this` parameter as their first argument — `Vessel.max_thrust`, `Flight.mean_altitude`, etc. — no longer take a `conn` argument before the `this` argument.  Instead, they use the connection from `this`.
* For example, `Vessel.max_thrust(conn, vessel)` becomes `Vessel.max_thrust(vessel)`.
* This also means functions are now chainable, e.g. `SpaceCenter.active_vessel(conn) |> Vessel.max_thrust()`.

### Optional arguments

* Functions that have arguments with default values, now expect those arguments in a `key: value` keyword list form.
* Said arguments can be omitted, and will send the default value if so.
* For example, `Vessel.flight(vessel, frame)` is now either `Vessel.flight(vessel, reference_frame: frame)`, or `Vessel.flight(vessel)` if the default value is desired.

### Stream changes

* New stream functions added:
  * `SpaceEx.Stream.start/2`
  * `SpaceEx.Stream.remove/2`
* Multiple attempts to stream the same data will no longer result in hanging behaviour.
  * Instead, they'll all reuse the same `Stream` process.
* Streams are no longer linked to the process that creates them.
  * This becomes dangerous behaviour when multiple independent streaming requests can result in using the same process.
  * Instead, they're linked to the `StreamConnection` process.
* The `StreamConnection` process is now linked to the `Connection` process.
  * They were previously "linked by proxy" via the process that created them, but became unlinked if that process exited normally.
  * Now, the `Connection`, `StreamConnection`, and all `Stream` processes are linked, and an error in any will take the whole connection stack down.
* Streams are now "bonded" to any process that requests their creation, even if they're being reused.
  * Calling `remove/2` will terminate the bond.
  * The stream will automatically shut itself down (and request removal from the server) if all bonds call `remove/2` or terminate.
* `Event.remove` added; delegates to `Stream.remove`.

### Other changes

* `Procedure.new` removed.
  * Procedures are now generated by internal methods on the service modules themselves; it no longer makes sense to manually create them.
* Connections now explicitly `Process.monitor` the process that launched them, and exit when that process does.
* Documentation now correctly lists parameters in `snake_case` rather than `camelCase`.
* Several KRPC functions are now marked as undocumented (hidden):
  * `add_stream`
  * `add_event`
  * `remove_stream`
  * `set_stream_rate`
  * `start_stream`
  * These functions are used internally by the `Event` and `Stream` classes and should not be used directly.
* Upgraded to Elixir 1.6:
  * All warnings fixed.
  * All code reformatted using the new auto-formatter.

## v0.4.0

* Complete rewrite of the API JSON parsing code.
  * The API should remain 100% the same, but the internals are much cleaner now.
  * All aspects of the JSON are parsed immediately under the `SpaceEx.API` module.
  * Types are parsed into `SpaceEx.API.Type.*` structs at compile time.
  * Runtime type encoding/decoding uses functions instead of macros.
  * Documentation now builds an index of cross-references and uses that instead of guesswork.

## v0.3.0

* `Stream.wait` added.
* Events added.
* sub_orbital_flight.exs and .craft added, ported from kRPC SubOrbitalFlight.py.  Provides example of Events.
* launch_into_orbit.craft added, and .exs made more true to original.
* **Breaking changes to RPC call syntax:**
  * All calls return their return value directly, not an `{:ok, value}` tuple.
  * `SpaceEx.Connection.RPCError` is raised on errors instead.
  * All `get_` and `static_` function prefixes are removed.
  * ExDoc examples and example scripts still need to be updated.

## v0.2.0

* Changelog created.
* Stream functionality added.
