# To-do list

## Cleanups

### Hide/rename core I/O functions

Certain functions like `KRPC.add_stream` should probably be marked as `@doc false` (or otherwise flagged as "don't use this"), because their behaviour is provided by core classes.

Of course, we can't just get rid of those functions, because they're actually used by the functionality in question.  But we can potentially rename them.

## Tests

Considering the API is automatically generated based on JSON definitions, the protocol is raw binary over TCP, and the server requires a running instance of a graphically intensive game with manual input required to set it up, I don't think SpaceEx will ever have full end-to-end integration tests, or particularly high test coverage across the entire API.

However, that certainly doesn't mean that tests are impossible.  It should be pretty easy to come up with a mock test object that expects certain requests and generates canned replies.  Maybe these could be recorded from live traffic, similar to ExVCR and similar "remote but not remote" test utilities.

Plus, simply testing that key functions exist, have the expected arity, and accept the expected object types would go a long way towards improving confidence while hacking on the library, particularly the `SpaceEx.Gen` macro code.

An early obvious candidate for testing are the type encoders and decoders.  These can be easily tested using both encoding/decoding between known values and binary strings, and encoding/decoding random values, with no remote server or mocking.

Current test protocol is to run all the scripts in `examples`.  This has moderately decent coverage, but is far from complete.
