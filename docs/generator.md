# Feature constants and the command-line tool

Feature constants carry each feature's key and type, so answers are typed to match:
`check(Features.aiCredits)` answers a `MeteredCheck`, and usage methods take only metered
features.

## Generating them

```sh
ENTITLER_KEY=ent_live_… swift run entitler generate --out Sources/App/EntitlerFeatures.swift
```

Or, through the command plugin, from your package's directory (SwiftPM asks once for network
and write access):

```sh
ENTITLER_KEY=ent_live_… swift package entitler-generate --out Sources/App/EntitlerFeatures.swift
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--out <file>` | `EntitlerFeatures.swift` | the file to write |
| `--key <key>` | `ENTITLER_KEY` | a key with `plans:read` |
| `--base-url <url>` | `https://api.entitler.dev` | the API's address |
| `--access-level <level>` | `internal` | `public`, `package` or `internal` |
| `--check` | | compare instead of writing; fails when out of date |
| `--allow-empty` | | write the file even when Entitler lists no features |
| `--help` | | print usage |

Each flag takes `--flag value` or `--flag=value`. `--check` ignores the `Read from` line, so a new
release with the same features stays up to date. Run it nightly and on `main` rather than as a
required pull request check, since forks have no key.

Generate from the live environment, with a key holding only `plans:read`: a test environment's All
customers track may follow an open change. When Entitler lists no features and the file already
holds constants, `generate` writes nothing and fails, so a key for the wrong environment never
empties the file; `--allow-empty` writes the empty file.

The output is an `enum Features` of constants sorted by key, formatted as swift-format leaves it:

```swift
enum ExampleFeatures {
  /// Export to PDF
  ///
  /// Download any document as a PDF.
  static let exportPDF = Feature<OnOff>("export_pdf")

  /// Team essentials
  ///
  /// Includes collaboration, support_extras.
  static let teamEssentials = Feature<FeatureGroup>(
    "team_essentials", includes: ["team_seats", "shared_folders"]
  )
}
```

## Names

Keys become lower camel case, with these initialisms in upper case after the API Design
Guidelines: AI, API, CSV, HTML, HTTP, HTTPS, ID, IP, JSON, PDF, SDK, SKU, SLA, SMS, SQL, SSO, UI,
URL, UUID and XML (`export_pdf` becomes `exportPDF`, `support_sla_hours` becomes
`supportSLAHours`; at the start of a name they stay lower case, as in `aiCredits`).

When the file exists, each constant keeps its name, so adding a feature never renames another. A
name that is a reserved word gains a trailing underscore (`default_`), and a name already taken
gains a number (`seats2`), decided in key order after the kept names. Features no longer listed
disappear. Archived features are marked `@available(*, deprecated, message: "Archived in Entitler.")`.
A feature of a type this SDK does not know becomes a plain key string.

## By hand

```swift
enum HandWrittenFeatures {
  static let sso = Feature<OnOff>("sso")
  static let seats = Feature<Config>("team_seats")
  static let credits = Feature<Metered>("ai_credits")
  static let team = Feature<FeatureGroup>("collaboration", includes: ["team_seats", "shared_folders"])
}
```

Build tooling can render the same file with `EntitlerGenerator.renderFeatures(_:accessLevel:existingSource:)`.

## Snapshot keys

`entitler snapshot-keys` writes the keys that verify [offline snapshots](offline-snapshots.md), for
your app to ship. It needs no key:

```sh
swift run entitler snapshot-keys --out Sources/App/SnapshotKeys.json
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--out <file>` | `entitler-snapshot-keys.json` | the JSON file to write |
| `--base-url <url>` | `https://api.entitler.dev` | the API's address |
| `--help` | | print usage |

It writes the key set two-space indented, through a temporary file moved into place, so a failed
run never leaves a partial file, and refuses to write an empty key set. Run it in an Xcode build
phase or a script before each release build, so key pinning needs no hand-written download.

Both commands exit 0 on success or when up to date, and 1 otherwise.
