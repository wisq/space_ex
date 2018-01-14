# To-do list

## Missing functionality

**These need to be addressed before 1.0.**  I can't rightfully call it a full release without these.

### Stream support

Streams are way better than polling over and over.  Getting them working is a fairly high priority.

### Events: Remote procedures and expressions

These are new since the last time I worked in kRPC, but they seem to provide a great next step in offloading parameter monitoring from the client to the server.

## Quality of life

### Default values for args

These are in the API JSON, but we currently ignore them and require all arguments at all times.

### ~~Generate bang functions (e.g. `get_x!`)~~ Return plain values, raise on error

~~I initially didn't like how cluttered these made things, but I think they're necessary.~~  Nobody wants to be checking for `{:ok, _}` on every single function call, it prevents any sort of nice-looking nested calling, and it just generally makes simple things difficult.

~~I'm *very* tentatively considering idea of just having the functions be "raise on error" by default.  But that *really* goes against The Elixir Way™ (as I understand it), and so I'm extremely hesitant to go down that road.  More thoughts and consultation needed.~~

**Update:** I've talked about this with some people on the Elixir community, and it didn't take much to convince me.  I'm going to have functions raise some sort of RPCError if they don't succeed, and just return the raw value, without the `{:ok, value}` tuples.  In their words:

> if you are doing RPC, just error everywhere

> errors in RPC are broken by design anyway

> and it is not like you are doing anything if you get a non ok right now

> you are already erroring

And it's hard to disagree with that.  I think the number of times someone will want to catch an error is going to be small compared to the number of times they'll just want to write simple, straightforward code that will raise if anything weird happens.

Since this is a major breaking change, I'm going to wait until version 1.0, to respect semantic versioning.

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

Since this is a major breaking change (decreases arity for all calls), I'm going to wait until version 1.0, to respect semantic versioning.

### Keyword-based function arguments

Some functions have a bunch of args, many of which are optional.  Most of the args are sensibly named (except `this`, which I may need to dynamically rename).  It might make sense to offer keyword-based versions, or to use keywords for the optional arguments.

*See above re: `object_or_tuple`; this will likely be what `this` gets renamed to.*

## Cleanups

### Fix static function naming

At first glance, I just need to ditch the `static_` part.  All my functions are effectively statics.  But before I do this, I want to think about whether having object-reference-based functions directly alongside "static" functions will cause any confusion.

*Hmm, I need to survey these methods to see what they all do, but maybe I should put them in a `.Util` module under their existing module?*

### Tests

Considering the API is automatically generated based on JSON definitions, the protocol is raw binary over TCP, and the server requires a running instance of a graphically intensive game with manual input required to set it up, I don't think SpaceEx will ever have full end-to-end integration tests, or particularly high test coverage across the entire API.

However, that certainly doesn't mean that tests are impossible.  It should be pretty easy to come up with a mock test object that expects certain requests and generates canned replies.  Maybe these could be recorded from live traffic, similar to ExVCR and similar "remote but not remote" test utilities.

Plus, simply testing that key functions exist, have the expected arity, and accept the expected object types would go a long way towards improving confidence while hacking on the library, particularly the `SpaceEx.Gen` macro code.
