# Contributing

## Setup

Install Swift 6.0 or newer: Xcode 16 or newer on macOS, or a toolchain from
[swift.org](https://www.swift.org/install/) on Linux. Clone the repository and build:

```sh
swift build
```

## Commands

| Command | What it does |
| --- | --- |
| `swift format lint --strict --recursive Sources Tests Plugins Package.swift` | lint and format check |
| `swift format --in-place --recursive Sources Tests Plugins Package.swift` | format |
| `swift build --build-tests -Xswiftc -warnings-as-errors` | build with warnings as errors |
| `swift test --skip EntitlerIntegrationTests --enable-code-coverage` | unit tests |
| `swift test --sanitize=thread --skip EntitlerIntegrationTests` | unit tests under Thread Sanitizer |
| `ENTITLER_TEST_KEY=sk_… swift test --filter EntitlerIntegrationTests` | live API tests |
| `ENTITLER_DOCS=1 swift package generate-documentation --target Entitler --target EntitlerTesting --target EntitlerGenerator --warnings-as-errors` | API reference |
| `python3 scripts/extract-snippets.py && (cd examples && swift build --build-tests && swift test --skip-build)` | examples and the snippets of the README and guides |
| `UPDATE_GOLDEN=1 swift test --filter GeneratorTests` | rewrite the generator's golden files |

Coverage must stay at or above 90% of lines; CI enforces it.

## Live API tests

The integration suite runs against `https://api.entitler.dev` with the key in `ENTITLER_TEST_KEY`
(the SDK project's development environment). Without it, the suite is skipped. Every customer it
creates has a unique `sdk-swift-…` id and is erased at the end, even when a test fails, so runs can
overlap. The suite never writes the catalogue, tracks or keys.

## Dependencies

The only runtime dependency is swift-crypto, linked on Linux alone. Its range stops below 4.4.0
because later releases need Swift tools 6.1 or newer, and SwiftPM 6.0 would fail to resolve
them.

## Releasing

1. Move the `Unreleased` notes in `CHANGELOG.md` under the new version and date.
2. Set `entitlerSDKVersion` in `Sources/Entitler/Version.swift` to the version.
3. Merge to `main`, then push a tag with the version and no `v`, such as `0.2.0`.

`release.yml` checks that the tag matches the version, runs every check, and creates the GitHub
release with the changelog's notes. The Swift Package Index picks up the tag on its own.
