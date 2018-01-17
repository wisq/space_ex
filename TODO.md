# To-do list

## Quality of life

### Default values for args

These are in the API JSON, but we currently ignore them and require all arguments at all times.

### Embed connection in object pointers

If I go ahead with this, it would allow you to do things like

```elixir
vessel = SpaceEx.SpaceCenter.get_active_vessel!(conn)
orbit = SpaceEx.SpaceCenter.Vessel.get_orbit!(vessel)
apoapsis = SpaceEx.SpaceCenter.Orbit.get_apoapsis_altitude!(orbit)
```

Note the lack of `conn` in lines 2 and 3.  The idea here is that — although you could always specify `conn` if you really want — by default, it'll use the same connection you used to retrieve the object.  This also allows the above code to be simplified down to

```elixir
apoapsis =
  SpaceEx.SpaceCenter.get_active_vessel!(conn)
  |> SpaceEx.SpaceCenter.Vessel.get_orbit!
  |> SpaceEx.SpaceCenter.Orbit.get_apoapsis_altitude!
```

I need to think about this a bit more, since I'm a bit concerned about having a bunch of different versions of the function all with subtle differences.  But if I give everything a proper struct type and do pattern matching on the arguments, it may not be too bad.

**Update:** I think what I'm going to do is, have the first argument be `object_or_tuple`, e.g. `vessel_or_tuple` for `Vessel` functions.  It will accept either *just* a `vessel` struct (with the `conn` embedded in it), or a `{conn, vessel}` tuple if you want to work with a different connection.  I may also add something like `Connection.claim(vessel)` (or `rehome` or something) to change the `conn` embedded in it.

This means that both versions will have the same arity, they won't clog the docs, etc.  I can describe the `conn_or_tuple` argument at the top of the page.

**Update 2:** Actually, I think I may ditch the tuple idea entirely, and just add maybe a `Connection.rehome` method that takes an object struct and updates the `conn` parameter to the specified connection.  If people are passing objects between connections a lot and want some sort of syntactic sugar for that, then I can fall back to the tuple idea.

### Keyword-based function arguments

Some functions have a bunch of args, many of which are optional.  Most of the args are sensibly named (except `this`, which I may need to dynamically rename).  It might make sense to offer keyword-based versions, or to use keywords for the optional arguments.

*See above re: `object_or_tuple`; this will likely be what `this` gets renamed to.*

## Cleanups

### Hide/rename core I/O functions

Certain functions like `KRPC.add_stream` should probably be marked as `@doc false` (or otherwise flagged as "don't use this"), because their behaviour is provided by core classes.

Of course, we can't just get rid of those functions, because they're actually used by the functionality in question.  But we can potentially rename them.

### Revisit encoding/decoding macros

Function argument encoding and return type decoding are currently baked in at compile time using macros.  This does have the advantage of ensuring that we never run into a "I don't know how to encode/decode this" error at runtime, and *may* have speed benefits, but it makes the encoders/decoders harder to run dynamically, and makes tracebacks all pretty useless.

I may be able to fix the tracebacks, either with `quote(location: keep)` or maybe something better.  But I should probably try converting them to dynamic runtime functions and seeing what impact that has on performance.  If the benefit is negligible, I may be better off just going that way instead.

As I see it, there's two ways to go:

1. Fully dynamic — pattern match on the type codes at runtime; and,
2. Semi-dynamic — parse types into e.g. `%ListType{subtype: ...}`, `%TupleType{subtypes: {...}`, `%ProtobufType{module: X}`, etc., and pattern match on that at runtime.

The #2 case has the advantage of ensuring we at least know about every type at compile time (ensuring completeness).

Even in the #1 case, we can still ensure completeness if we have a test suite that tests every known type, and then walks the API JSON and ensures there aren't any types we haven't tested.

### Tests

Considering the API is automatically generated based on JSON definitions, the protocol is raw binary over TCP, and the server requires a running instance of a graphically intensive game with manual input required to set it up, I don't think SpaceEx will ever have full end-to-end integration tests, or particularly high test coverage across the entire API.

However, that certainly doesn't mean that tests are impossible.  It should be pretty easy to come up with a mock test object that expects certain requests and generates canned replies.  Maybe these could be recorded from live traffic, similar to ExVCR and similar "remote but not remote" test utilities.

Plus, simply testing that key functions exist, have the expected arity, and accept the expected object types would go a long way towards improving confidence while hacking on the library, particularly the `SpaceEx.Gen` macro code.
