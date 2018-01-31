# To-do list

## Improve the `SpaceEx.Stream.subscribe/2` interface

I'm thinking that clients will be able to subscribe to the next `n` values instead of just one value.  The number of values remaining (i.e. the remaining subscription duration) will be delivered with each message, meaning processes can e.g. resubscribe when they get down to a certain number remaining.

I also want to send the time the value was received.  As such, clients can choose between three different approaches to rate control:

* "Don't care" — The default approach.  Receive values as they come.  Re-subscribe when remaining items **equals¹** a low water mark.
  * If your subscription runs out, you'll just have periods of missed events.
  * You may be parsing older events.
* "Must not miss an event" — per default, except raise if remaining items ever reaches zero (i.e. subscription expired).
  * If your subscription runs out, you'll raise an error.
  * You may be parsing older events.
* "Must be real-time data" — per default, except throw out any values where the delta between `time` and `now` is too high.
  * You'll never be parsing older events.
  * You're less likely to have your subscription run out, because throwing away old data is a very fast way to stay caught up.

It would also be cool if there was a way to retrieve this time value from `get` and `wait`.  Maybe as an optional structure, or a second part of a tuple.

¹ It's important that you renew when *equal to* a number, rather than *less than* a number.  Otherwise, you issue a resubscription request for *every message* below the threshold.  This should be stressed in the docs.
