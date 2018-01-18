# Changelog

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
