# Versioning and support

The SDK follows semantic versioning. Releases are git tags such as `0.1.0` (no `v`), and the
changes are in the [changelog](../CHANGELOG.md). Before 1.0, a minor release may change the public
API.

Supported:

- Swift 6.0 and newer.
- iOS 15, macOS 12, tvOS 15, watchOS 8 and visionOS 1, and newer.
- Linux with the official Swift toolchains for those Swift versions.

The SDK takes no dependency on Apple platforms. On Linux it uses swift-crypto for snapshot
signatures, and FoundationNetworking for `URLSession`.

The SDK tracks the live API: unknown fields are ignored and unknown values are kept, so an older
SDK keeps working as the API grows.

Report security issues privately; see [SECURITY.md](../SECURITY.md).
