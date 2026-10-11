import Foundation
import Testing

@testable import Entitler
@testable import EntitlerGenerator

enum Golden {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Golden")

  static func check(_ text: String, _ name: String) throws {
    let url = directory.appendingPathComponent(name)
    if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] != nil {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
    }
    let golden = try String(contentsOf: url, encoding: .utf8)
    #expect(text == golden)
  }
}

func featureList(_ features: String, release: String = "2", change: String = "null") -> FeatureList
{
  let json =
    #"{"environment":{"id":"e","name":"development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":\#(release),"change":\#(change),"features":[\#(features)]}"#
  return try! JSON.decoder().decode(FeatureList.self, from: Data(json.utf8))
}

func feature(
  _ key: String, _ type: String, name: String? = nil, description: String = "", unit: String = "",
  archived: Bool = false, includes: [String] = []
) -> String {
  let includes = includes.map { "\"\($0)\"" }.joined(separator: ",")
  return
    #"{"id":"\#(key)","key":"\#(key)","name":"\#(name ?? key)","type":"\#(type)","description":"\#(description)","unit":"\#(unit)","resetEvery":null,"archived":\#(archived),"includes":[\#(includes)]}"#
}

let sampleCatalogue = [
  feature(
    "team_essentials", "group", name: "Team essentials",
    description: "Everything a team needs, as one unit.",
    includes: ["collaboration", "support_extras"]),
  feature(
    "ai_credits", "metered", name: "AI credits", description: "Spent on AI actions each month.",
    unit: "credits"),
  feature(
    "collaboration", "group", name: "Collaboration", description: "Working with other people.",
    includes: ["team_seats", "shared_folders"]),
  feature(
    "export_pdf", "boolean", name: "Export to PDF", description: "Download any document as a PDF."),
  feature(
    "priority_support", "boolean", name: "Priority support", description: "Jump the support queue."),
  feature(
    "shared_folders", "boolean", name: "Shared folders",
    description: "Folders the whole workspace can see."),
  feature(
    "sso", "boolean", name: "Single sign-on",
    description: "Log in through the customer's identity provider."),
  feature(
    "support_contacts", "config", name: "Support contacts",
    description: "People who can open tickets.", unit: "contacts"),
  feature(
    "support_extras", "group", name: "Support extras",
    description: "Priority queue plus a reply-time promise.",
    includes: ["priority_support", "support_sla_hours"]),
  feature(
    "support_sla_hours", "config", name: "Support SLA", description: "Hours until the first reply.",
    unit: "hours"),
  feature(
    "team_seats", "config", name: "Team seats", description: "People who can join a workspace.",
    unit: "seats"),
].joined(separator: ",")

@Suite struct GeneratorTests {
  @Test func rendersTheSampleCatalogue() throws {
    try Golden.check(renderFeatures(featureList(sampleCatalogue)), "SampleFeatures.swift.txt")
  }

  @Test func namesFollowTheGuidelines() {
    #expect(featureConstantName(for: "export_pdf") == "exportPDF")
    #expect(featureConstantName(for: "support_sla_hours") == "supportSLAHours")
    #expect(featureConstantName(for: "ai_credits") == "aiCredits")
    #expect(featureConstantName(for: "api_url_id") == "apiURLID")
    #expect(featureConstantName(for: "sso") == "sso")
    #expect(featureConstantName(for: "seats_v2") == "seatsV2")
  }

  @Test func escapesReservedAndTakenNamesAndRendersEdgeCases() throws {
    let list = featureList(
      [
        feature("default", "boolean"), feature("self", "boolean"), feature("a_b", "boolean"),
        feature("a__b", "config"),
        feature("ab", "boolean"),
        feature(
          "old_reports", "boolean", name: "", description: "Line one.\\nLine two.", archived: true),
        feature("hologram", "quantum"),
        feature("loop_a", "group", includes: ["loop_b", "sso_x", "missing", "sso_x"]),
        feature("loop_b", "group", includes: ["loop_a", "sso_x"]),
        feature("sso_x", "boolean"),
        feature(
          "everything_in_a_very_long_group_name_for_wrapping", "group",
          includes: (1...12).map { "member_feature_\($0)" }),
        feature(
          "medium_group_name", "group",
          includes: ["member_feature_1", "member_feature_2", "member_feature_3"]),
      ].joined(separator: ",") + ","
        + (1...12).map { feature("member_feature_\($0)", "boolean") }.joined(separator: ","),
      release: "null", change: #""chg_42""#)
    try Golden.check(renderFeatures(list, accessLevel: .public), "EdgeFeatures.swift.txt")
  }

  @Test func keepsExistingNamesAndDropsUnlistedFeatures() throws {
    let existing = """
      enum Features {
        static let pdfExport = Feature<OnOff>("export_pdf")
        static let `gone` = Feature<OnOff>("removed")
        static let groupOfThings = Feature<FeatureGroup>(
          "collaboration", includes: ["team_seats"])
        static let credits = "ai_credits"
      }
      """
    let names = existingFeatureNames(in: existing)
    #expect(
      names == [
        "export_pdf": "pdfExport", "removed": "gone", "collaboration": "groupOfThings",
        "ai_credits": "credits",
      ])
    let list = featureList(
      [
        feature("export_pdf", "boolean"), feature("export_p_d_f", "boolean"),
        feature("ai_credits", "metered"),
      ].joined(separator: ","))
    let source = renderFeatures(
      list,
      existingSource: existing + "\n static let exportPDF = Feature<OnOff>(\"taken_elsewhere\")")
    #expect(source.contains("static let pdfExport = Feature<OnOff>(\"export_pdf\")"))
    #expect(source.contains("static let credits = Feature<Metered>(\"ai_credits\")"))
    #expect(source.contains("static let exportPDF = Feature<OnOff>(\"export_p_d_f\")"))
    #expect(!source.contains("removed"))
  }

  @Test func rendersAnEmptyList() throws {
    try Golden.check(renderFeatures(featureList("")), "EmptyFeatures.swift.txt")
  }
}

@Suite struct GeneratorCommandTests {
  func run(
    _ arguments: [String], api: FakeAPI, environment: [String: String] = ["ENTITLER_KEY": "sk_env"]
  ) async -> (Int32, [String]) {
    let lines = Box<[String]>([])
    let code = await api.run {
      await GeneratorCommand.run(arguments, environment: environment, options: api.options()) {
        line in lines.with { $0.append(line) }
      }
    }
    return (code, lines.get)
  }

  func temporaryFile() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "entitler-\(UUID().uuidString).swift"
    ).path
  }

  func catalogue(_ features: String, release: Int = 2) -> Reply {
    .json(
      #"{"environment":{"id":"e","name":"development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":\#(release),"change":null,"features":[\#(features)]}"#
    )
  }

  @Test func writesThenChecks() async throws {
    let api = FakeAPI { _ in .json("{}") }
    api.answer { [self] _ in catalogue(sampleCatalogue) }
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: file) }
    var (code, lines) = await run(["generate", "--out", file], api: api)
    #expect(code == 0)
    #expect(lines == ["Wrote 11 features to \(file)."])
    #expect(api.last.path == "/pricing/features")
    #expect(api.last.header("Authorization") == "Bearer sk_env")
    (code, lines) = await run(["generate", "--out=\(file)", "--check", "--key=sk_flag"], api: api)
    #expect(code == 0)
    #expect(lines == ["\(file) is up to date with 11 features."])
    #expect(api.last.header("Authorization") == "Bearer sk_flag")
    api.answer { [self] _ in catalogue(sampleCatalogue, release: 3) }
    (code, lines) = await run(["generate", "--out", file, "--check"], api: api)
    #expect(code == 0)
    api.answer { [self] _ in catalogue(feature("sso", "boolean")) }
    (code, lines) = await run(["generate", "--out", file, "--check"], api: api)
    #expect(code == 1)
    #expect(lines == ["\(file) is out of date. Run entitler generate to update it."])
    (code, lines) = await run(["generate", "--out", file, "--access-level", "public"], api: api)
    #expect(lines == ["Wrote 1 feature to \(file)."])
    #expect(try String(contentsOfFile: file, encoding: .utf8).contains("public static let sso"))
  }

  @Test func checkFailsWhenTheFileIsMissing() async {
    let api = FakeAPI { [self] _ in catalogue("") }
    let file = temporaryFile()
    let (code, lines) = await run(["generate", "--out", file, "--check"], api: api)
    #expect(code == 1)
    #expect(lines == ["\(file) is out of date. Run entitler generate to update it."])
  }

  @Test func usageAndArgumentErrors() async {
    let api = FakeAPI()
    var (code, lines) = await run([], api: api)
    #expect(code == 1)
    #expect(lines == [GeneratorCommand.usage])
    (code, lines) = await run(["--help"], api: api)
    #expect(code == 0)
    (code, lines) = await run(["generate", "--help"], api: api)
    #expect(code == 0)
    #expect(lines == [GeneratorCommand.usage])
    (code, lines) = await run(["publish"], api: api)
    #expect(code == 1)
    (code, lines) = await run(["generate", "--nope"], api: api)
    #expect(code == 1)
    #expect(lines.first?.hasPrefix("Unknown option --nope.") == true)
    (code, lines) = await run(["generate", "--out"], api: api)
    #expect(code == 1)
    (code, lines) = await run(["generate", "--access-level", "private"], api: api)
    #expect(code == 1)
    (code, lines) = await run(["generate", "--base-url", "not a url"], api: api)
    #expect(code == 1)
    (code, lines) = await run(["generate"], api: api, environment: [:])
    #expect(code == 1)
    #expect(
      lines == [
        "Provide an API key with --key or set ENTITLER_KEY. The key needs the plans:read scope."
      ])
    #expect(api.count == 0)
  }

  @Test func anEmptyListNeverEmptiesAnExistingFile() async throws {
    let api = FakeAPI { [self] _ in catalogue(feature("sso", "boolean")) }
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: file) }
    var (code, lines) = await run(["generate", "--out", file], api: api)
    #expect(code == 0)
    let written = try String(contentsOfFile: file, encoding: .utf8)
    api.answer { [self] _ in catalogue("") }
    (code, lines) = await run(["generate", "--out", file], api: api)
    #expect(code == 1)
    #expect(
      lines == [
        "Entitler listed no features, so \(file) was left as it is. Check the key's environment, or pass --allow-empty."
      ])
    #expect(try String(contentsOfFile: file, encoding: .utf8) == written)
    (code, lines) = await run(["generate", "--out", file, "--allow-empty"], api: api)
    #expect(code == 0)
    #expect(lines == ["Wrote 0 features to \(file)."])
    (code, lines) = await run(["generate", "--out", file], api: api)
    #expect(code == 0)
  }

  @Test func snapshotKeysAreWrittenWithoutAKey() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"keys":[{"kty":"EC","crv":"P-256","x":"x1","y":"y1","kid":"k1","alg":"ES256","use":"sig"},{"kty":"EC","crv":"P-256","x":"x2","y":"y2","kid":"k2","alg":"ES256","use":"sig"}]}"#
      )
    }
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: file) }
    var (code, lines) = await run(
      ["snapshot-keys", "--out", file], api: api, environment: [:])
    #expect(code == 0)
    #expect(lines == ["Wrote 2 snapshot keys to \(file)."])
    #expect(api.last.path == "/customers/snapshot-keys")
    #expect(api.last.header("Authorization") == nil)
    let written = try String(contentsOfFile: file, encoding: .utf8)
    #expect(
      written.hasPrefix(
        "{\n  \"keys\": [\n    {\n      \"kty\": \"EC\",\n      \"crv\": \"P-256\","))
    #expect(written.hasSuffix("\n    }\n  ]\n}\n"))
    let decoded = try JSONDecoder().decode(SnapshotKeys.self, from: Data(written.utf8))
    #expect(decoded.keys.map(\.kid) == ["k1", "k2"])
    api.answer { _ in
      .json(
        #"{"keys":[{"kty":"EC","crv":"P-256","x":"x","y":"y","kid":"k","alg":"ES256","use":"sig"}]}"#
      )
    }
    (code, lines) = await run(["snapshot-keys", "--out=\(file)"], api: api)
    #expect(lines == ["Wrote 1 snapshot key to \(file)."])
    api.answer { _ in .json(#"{"keys":[]}"#) }
    (code, lines) = await run(["snapshot-keys", "--out", file], api: api)
    #expect(code == 1)
    #expect(lines == ["Entitler published no snapshot keys, so \(file) was left as it is."])
    #expect(try String(contentsOfFile: file, encoding: .utf8).contains("\"kid\": \"k\""))
    (code, lines) = await run(["snapshot-keys", "--help"], api: api)
    #expect(code == 0)
    (code, lines) = await run(["snapshot-keys", "--key", "k"], api: api)
    #expect(code == 1)
    api.answer { _ in .error(503, code: "unavailable", message: "Down.") }
    (code, lines) = await run(["snapshot-keys", "--out", file], api: api)
    #expect(code == 1)
    #expect(lines == ["Entitler request failed: Down (unavailable)."])
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(
      "entitler-\(UUID().uuidString)/keys.json"
    ).path
    api.answer { _ in
      .json(
        #"{"keys":[{"kty":"EC","crv":"P-256","x":"x","y":"y","kid":"k","alg":"ES256","use":"sig"}]}"#
      )
    }
    (code, lines) = await run(["snapshot-keys", "--out", missing], api: api)
    #expect(code == 1)
    #expect(lines.first?.hasPrefix("Could not write \(missing)") == true)
  }

  @Test func apiFailuresAreReported() async {
    let api = FakeAPI { _ in
      .error(403, code: "scope_required", message: "The key needs plans:read.")
    }
    var (code, lines) = await run(["generate", "--out", temporaryFile()], api: api)
    #expect(code == 1)
    #expect(lines == ["Entitler request failed: The key needs plans:read (scope_required)."])
    api.answer { _ in .failure(.cannotConnectToHost) }
    (code, lines) = await run(["generate", "--base-url", "https://\(api.host)"], api: api)
    #expect(code == 1)
    #expect(lines.first?.hasPrefix("Entitler request failed: ") == true)
  }
}
