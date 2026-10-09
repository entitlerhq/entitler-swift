# Feature constants and the generator

Feature constants carry each feature's key and type, so answers are typed to match:
`check(Features.aiCredits)` answers a `MeteredCheck`, and usage methods take only metered
features.

## Generating them

```sh
ENTITLER_KEY=sk_… swift run entitler generate --out Sources/App/EntitlerFeatures.swift
```

Or, through the command plugin, from your package's directory (SwiftPM asks once for network
and write access):

```sh
ENTITLER_KEY=sk_… swift package entitler-generate --out Sources/App/EntitlerFeatures.swift
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--out <file>` | `EntitlerFeatures.swift` | the file to write |
| `--key <key>` | `ENTITLER_KEY` | a key with `plans:read` |
| `--base-url <url>` | `https://api.entitler.dev` | the API's address |
| `--access-level <level>` | `internal` | `public`, `package` or `internal` |
| `--check` | | compare instead of writing; fails when out of date |
| `--help` | | print usage |

Each flag takes `--flag value` or `--flag=value`. `--check` ignores the `Read from` line, so a new
release with the same features stays up to date; run it in CI.

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
