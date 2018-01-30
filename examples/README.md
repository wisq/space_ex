# Examples

SpaceEx currently has two examples, based on the [Tutorials & Examples](https://krpc.github.io/krpc/tutorials.html) scripts for other languages:

* ["Sub-orbital flight"](sub-orbital-flight) launches a craft to an altitude of 100km and then performs a reentry and parachute landing.
* ["Launch into orbit"](launch-into-orbit) launches a craft to a 150km circular orbit.

In each case, we start with a literal translation of the source script, and then iteratively improve it (WIP) into a version that better takes advantage of Elixir's multi-process capabilities.

Each example comes with its own `.craft` file, which should be copied to your Kerbal `Ships/VAB` directory and 
