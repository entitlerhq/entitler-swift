# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-09

### Added

- `EntitlerServer`, built from a secret key, and `EntitlerClient`, built from a customer token or
  a publishable key and an identity token, with token providers that refresh.
- One `Customer` protocol for both: checks, `isEntitled(to:default:)`, entitlements, plan space,
  pricing, usage with gate and observe modes, holds, `withHold`, and snapshots.
- Registration, details, tokens, tracks, self-serve billing and vendor actions on `ServerCustomer`.
- Usage batches, pricing, the feature list, scopes and snapshot keys on the server.
- Timeouts, retries with backoff, idempotency keys on every write, an answer cache honouring
  `max-age` and `ETag`, and stale answers while Entitler is unreachable.
- Offline snapshot verification with CryptoKit, or swift-crypto on Linux.
- The `entitler generate` command and the `entitler-generate` plugin for typed feature constants.

[Unreleased]: https://github.com/entitlerhq/entitler-swift/compare/0.1.0...HEAD
[0.1.0]: https://github.com/entitlerhq/entitler-swift/releases/tag/0.1.0
