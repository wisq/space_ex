# To-do list

## Missing functionality

### Stream support

Streams are way better than polling over and over.  Getting them working is a fairly high priority.

### Events: Remote procedures and expressions

These are new since the last time I worked in kRPC, but they seem to provide a great next step in offloading parameter monitoring from the client to the server.

## Quality of life

### Default values for args

These are in the API JSON, but we currently ignore them and require all arguments at all times.

### Generate bang functions (e.g. `get_x!`)

I initially didn't like how cluttered these made things, but I think they're necessary.  Nobody wants to be checking for `{:ok, _}` on every single function call, it prevents any sort of nice-looking nested calling, and it just generally makes simple things difficult.

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

### Keyword-based function arguments

Some functions have a bunch of args, many of which are optional.  Most of the args are sensibly named (except `this`, which I may need to dynamically rename).  It might make sense to offer keyword-based versions, or to use keywords for the optional arguments.
