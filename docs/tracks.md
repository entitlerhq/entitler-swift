# Tracks

A track decides the catalogue on sale to its customers: their plans, upgrade paths and where new
purchases go. Every customer starts on All customers. Put one on another track, such as a beta,
from your server:

```swift
let moved = try await customer.setTrack("trk_beta")
print("Now on", moved.track.name)
try await customer.setTrack(nil)
```

`nil` returns the customer to All customers. A closed track answers `409 track_closed`. Setting a
track needs `tracks:assign`, which no customer or identity token holds, since a test-money track
is free access.

Every answer with context names the customer's `track`, and the `release` or `change` it serves.
