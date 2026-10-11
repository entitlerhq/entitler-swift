# Tracks

A track decides the catalogue on sale to its customers: their plans, upgrade paths and where new
purchases go. Every customer starts on All customers. Put one on another track, such as a beta,
from your server:

```swift
let moved = try await customer.setTrack("Beta")
print("Now on", moved.track.name)
try await customer.setTrack(nil)
```

A track is named by its name, which is the same in every environment; `nil` returns the customer
to All customers. An unknown name answers `404 not_found`, and a closed track `409 track_closed`.
Setting a track needs `tracks:assign`, which no customer or identity token holds, since a
test-money track is free access. The server key preset lacks it, so a key minted from that preset
answers `403 scope_required` until you add the scope to the key.

Every answer with context names the customer's `track`, and the `release` or `change` it serves.
