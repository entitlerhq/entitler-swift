# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-11

### Added

- `EntitlerServer`, built from a secret key, and `EntitlerClient`, built from a customer token, a
  publishable key and an identity token, or a publishable key alone for signed-out pricing, with
  token providers that refresh. Each client refuses the other kind of key, and `close()` ends one.
- One `Customer` protocol for both: checks with `revalidate`, `isEntitled(to:default:)`,
  entitlements, `plans()`, pricing, usage with gate and observe modes and required idempotency
  keys, `startHold` handles and `withHold`, snapshots, and the customer's own billing choices:
  `subscribe` answering its next step, `cancel`, `undoPendingChange`, `billingPortal` and
  `syncBilling`.
- Registration, details, `erase()`, tokens, tracks by name, per-call `asOf` reads and the company's
  decisions on `ServerCustomer`: `setPlan` with billing modes and `until`, `setAddOn`, grants,
  `adjustMeter` and `cancelUsage`.
- Usage batches with request keys derived from their events, pricing, the feature list, scopes and
  snapshot keys on the server.
- Timeouts, retries with backoff, idempotency keys on every write with `replayed` on their answers,
  an answer cache honouring `max-age` and `ETag`, and stale answers while Entitler is unreachable.
- Offline snapshot verification with CryptoKit, or swift-crypto on Linux.
- The `entitler generate` and `entitler snapshot-keys` commands, and the `entitler-generate`
  plugin.
- `EntitlerTesting`: `FakeCustomer` and `FakeAnswers` for apps' own tests.

[Unreleased]: https://github.com/entitlerhq/entitler-swift/compare/0.1.0...HEAD
[0.1.0]: https://github.com/entitlerhq/entitler-swift/releases/tag/0.1.0
