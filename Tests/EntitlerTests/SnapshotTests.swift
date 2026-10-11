import Foundation
import Testing

@testable import Entitler

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

struct Signer {
  let key = P256.Signing.PrivateKey()
  let kid: String

  init(kid: String = "key_1") { self.kid = kid }

  var jwk: JSONWebKey {
    let raw = key.publicKey.rawRepresentation
    return JSONWebKey(
      kty: "EC", crv: "P-256", x: Base64URL.encode(raw.prefix(32)),
      y: Base64URL.encode(raw.suffix(32)),
      kid: kid, alg: "ES256", use: "sig")
  }

  func sign(header: [String: Any]? = nil, claims: [String: Any]) -> String {
    let header = header ?? ["typ": "entitlements+jwt", "alg": "ES256", "kid": kid]
    let head = Base64URL.encode(try! JSONSerialization.data(withJSONObject: header))
    let body = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
    let signature = try! key.signature(for: Data("\(head).\(body)".utf8))
    return "\(head).\(body).\(Base64URL.encode(signature.rawRepresentation))"
  }
}

extension JSONWebKey {
  init(kty: String, crv: String, x: String, y: String, kid: String, alg: String, use: String) {
    let json =
      #"{"kty":"\#(kty)","crv":"\#(crv)","x":"\#(x)","y":"\#(y)","kid":"\#(kid)","alg":"\#(alg)","use":"\#(use)"}"#
    self = try! JSONDecoder().decode(JSONWebKey.self, from: Data(json.utf8))
  }
}

@Suite struct SnapshotTests {
  static let now = Date(timeIntervalSince1970: 1_800_000_000)

  static func claims(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
    var claims: [String: Any] = [
      "iss": "https://api.entitler.dev/customers", "sub": "user_1",
      "environment": ["id": "env_1"], "track": ["id": "trk_1", "name": "All customers"],
      "release": 2, "change": NSNull(), "testers": true,
      "entitlements": [
        ["key": "export_pdf", "type": "boolean", "entitled": true, "value": true, "sources": []],
        [
          "key": "team", "type": "group", "entitled": false, "value": 0,
          "sources": [["type": "group", "features": ["seats"]]],
        ],
      ],
      "iat": 1_799_999_000, "exp": 1_800_003_600,
    ]
    change(&claims)
    return claims
  }

  func expectation(_ signer: Signer, now: Date = now, skew: Int = 60) -> SnapshotExpectation {
    SnapshotExpectation(
      keys: [signer.jwk], customer: "user_1", environment: "env_1", now: now, clockSkewSeconds: skew
    )
  }

  func failure(_ token: String, _ expected: SnapshotExpectation) -> SnapshotError? {
    do {
      _ = try verifySnapshot(token, expecting: expected)
      return nil
    } catch EntitlerError.snapshot(let error) {
      return error
    } catch {
      return nil
    }
  }

  @Test func verifiesAGoodSnapshot() throws {
    let signer = Signer()
    let snapshot = try verifySnapshot(
      signer.sign(claims: Self.claims()), expecting: expectation(signer))
    #expect(snapshot.customer == "user_1")
    #expect(snapshot.environment.id == "env_1")
    #expect(snapshot.release == 2)
    #expect(snapshot.testers)
    #expect(snapshot.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
    #expect(snapshot.entitlements.has("export_pdf"))
    #expect(!snapshot.entitlements.has("team"))
    #expect(snapshot.entitlements.asOf == Date(timeIntervalSince1970: 1_799_999_000))
    #expect(snapshot.entitlements.experiment == nil)
    #expect(snapshot.entitlements.environment == nil)
  }

  @Test func acceptsAKeySetAndPicksTheKeyByID() throws {
    let signer = Signer(kid: "b")
    let other = Signer(kid: "a")
    let set = try JSONDecoder().decode(
      SnapshotKeys.self, from: JSONEncoder().encode(["keys": [other.jwk, signer.jwk]]))
    let expected = SnapshotExpectation(
      keys: set, customer: "user_1", environment: "env_1", now: Self.now)
    _ = try verifySnapshot(signer.sign(claims: Self.claims()), expecting: expected)
    let client = try EntitlerServer(key: "k")
    _ = try client.verifySnapshot(signer.sign(claims: Self.claims()), expecting: expected)
    _ = try EntitlerClient(token: "t").verifySnapshot(
      signer.sign(claims: Self.claims()), expecting: expected)
  }

  @Test func refusesMalformedTokens() {
    let signer = Signer()
    let message = "That is not an entitlements snapshot. Pass the token snapshot() returned."
    for token in [
      "nope", "a.b", "a.b.c.d", "!!.b.c",
      signer.sign(header: ["typ": "JWT", "alg": "ES256", "kid": "key_1"], claims: Self.claims()),
      signer.sign(
        header: ["typ": "entitlements+jwt", "alg": "RS256", "kid": "key_1"], claims: Self.claims()),
    ] {
      let error = failure(token, expectation(signer))
      #expect(error?.code == .invalid)
      #expect(error?.message == message)
    }
  }

  @Test func refusesUnknownKeys() {
    let error = failure(Signer(kid: "other").sign(claims: Self.claims()), expectation(Signer()))
    #expect(
      error?.message
        == "None of the keys passed signed this snapshot. Fetch them again with snapshotKeys().")
  }

  @Test func refusesChangedSnapshotsAndBadKeys() {
    let signer = Signer()
    let token = signer.sign(claims: Self.claims())
    let parts = token.split(separator: ".")
    let forged = Base64URL.encode(
      try! JSONSerialization.data(withJSONObject: Self.claims { $0["sub"] = "someone" }))
    let changed = "\(parts[0]).\(forged).\(parts[2])"
    #expect(
      failure(changed, expectation(signer))?.message
        == "This snapshot was changed after Entitler signed it.")
    var expected = expectation(signer)
    expected.keys = [
      JSONWebKey(kty: "EC", crv: "P-256", x: "AA", y: "AA", kid: "key_1", alg: "ES256", use: "sig")
    ]
    #expect(
      failure(token, expected)?.message == "This snapshot was changed after Entitler signed it.")
    #expect(
      failure("\(parts[0]).\(parts[1]).AAAA", expectation(signer))?.message
        == "This snapshot was changed after Entitler signed it.")
  }

  @Test(arguments: [
    "iss", "sub", "environment", "track", "release", "change", "testers", "entitlements", "iat",
    "exp",
  ])
  func refusesClaimsOfTheWrongShape(claim: String) {
    let signer = Signer()
    let token = signer.sign(
      claims: Self.claims {
        $0[claim] =
          ["release", "change"].contains(claim)
          ? [1] : ["iss", "sub"].contains(claim) ? 5 : "wrong" as Any
      })
    #expect(
      failure(token, expectation(signer))?.message
        == "That is not an entitlements snapshot. Pass the token snapshot() returned.")
  }

  @Test func refusesPaymentsWithoutTesters() {
    let signer = Signer()
    let token = signer.sign(
      claims: Self.claims {
        $0["testers"] = nil
        $0["payments"] = "test"
      })
    #expect(failure(token, expectation(signer))?.code == .invalid)
  }

  @Test func refusesAnotherIssuer() {
    let signer = Signer()
    let token = signer.sign(claims: Self.claims { $0["iss"] = "https://evil.test" })
    #expect(
      failure(token, expectation(signer))?.message
        == "This snapshot was not issued by https://api.entitler.dev/customers.")
  }

  @Test func refusesSnapshotsSignedInTheFutureBeyondTheSkew() {
    let signer = Signer()
    let token = signer.sign(claims: Self.claims { $0["iat"] = 1_800_000_061 })
    #expect(
      failure(token, expectation(signer))?.message
        == "This snapshot was signed for 2027-01-15T08:01:01.000Z, which is still to come. Fetch a new one while online."
    )
    #expect(
      failure(signer.sign(claims: Self.claims { $0["iat"] = 1_800_000_060 }), expectation(signer))
        == nil)
    #expect(failure(token, expectation(signer, skew: 300)) == nil)
    #expect(
      failure(
        signer.sign(claims: Self.claims { $0["iat"] = 1_800_000_001 }), expectation(signer, skew: 0)
      ) != nil)
  }

  @Test func refusesExpiredSnapshots() {
    let signer = Signer()
    let token = signer.sign(claims: Self.claims { $0["exp"] = 1_800_000_000 })
    let error = failure(token, expectation(signer))
    #expect(error?.code == .expired)
    #expect(
      error?.message
        == "This snapshot expired at 2027-01-15T08:00:00.000Z. Fetch a new one while online.")
  }

  @Test func refusesAnotherCustomerOrEnvironment() {
    let signer = Signer()
    var expected = expectation(signer)
    expected.customer = "user_2"
    #expect(
      failure(signer.sign(claims: Self.claims()), expected)?.message
        == "This snapshot is for another customer, not user_2. Fetch one for the signed-in customer while online."
    )
    expected = expectation(signer)
    expected.environment = "env_2"
    #expect(
      failure(signer.sign(claims: Self.claims()), expected)?.message
        == "This snapshot is from another environment, not env_2. Fetch one from your app's environment while online."
    )
  }

  @Test func refusesSkewsOutsideTheRange() {
    let signer = Signer()
    for skew in [-1, 301] {
      #expect(
        throws: ArgumentError(message: "Pass clockSkewSeconds as a whole number from 0 to 300.")
      ) {
        try verifySnapshot(
          signer.sign(claims: Self.claims()), expecting: expectation(signer, skew: skew))
      }
    }
  }

  @Test func usesTheSystemClockByDefault() {
    let signer = Signer()
    let expected = SnapshotExpectation(keys: [signer.jwk], customer: "user_1", environment: "env_1")
    #expect(
      failure(signer.sign(claims: Self.claims()), expected)?.message.contains("still to come")
        == true)
  }
}

@Suite struct ModelTests {
  @Test func featureValuesRoundTrip() throws {
    let values = try JSONDecoder().decode(
      [FeatureValue].self, from: Data(#"[true, 0, 12, "unlimited"]"#.utf8))
    #expect(values == [.on, .amount(0), .amount(12), .unlimited])
    #expect(
      String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        == #"[true,0,12,"unlimited"]"#)
    #expect(values.map(\.description) == ["on", "0", "12", "unlimited"])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FeatureValue.self, from: Data("false".utf8))
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FeatureValue.self, from: Data(#""lots""#.utf8))
    }
  }

  @Test func featureConstantsCarryTheirType() {
    #expect(Feature<OnOff>("sso").type == .boolean)
    #expect(Feature<Config>("seats").type == .config)
    #expect(Feature<Metered>("credits").type == .metered)
    let group = Feature<FeatureGroup>("team", includes: ["a", "b"])
    #expect(group.type == .group)
    #expect(group.includes == ["a", "b"])
    #expect(group.description == "team")
    #expect(Feature<OnOff>("sso").includes.isEmpty)
  }

  @Test func unknownEnumValuesAreKept() throws {
    let types = try JSONDecoder().decode(
      [FeatureType].self, from: Data(#"["boolean","config","metered","group","quantum"]"#.utf8))
    #expect(types == [.boolean, .config, .metered, .group, .unknown("quantum")])
    #expect(
      String(decoding: try JSONEncoder().encode(types), as: UTF8.self)
        == #"["boolean","config","metered","group","quantum"]"#)
  }

  @Test func scopesKeepOnlyKnownOnesInOrder() {
    #expect(
      Scope.known(["org:manage", "plans:publish", "plans:read"]) == [.plansRead, .orgManage])
    #expect(
      Scope.allCases.map(\.rawValue) == [
        "plans:read", "entitlements:read", "usage:read", "usage:write", "billing:self",
        "customers:register", "customers:read", "customers:write", "customers:profile",
        "customers:sample", "tokens:mint", "plans:write", "plans:release", "tracks:manage",
        "tracks:promote", "tracks:assign", "keys:manage", "members:manage", "projects:manage",
        "org:manage",
      ])
  }

  @Test func instantsParseAnyOffset() {
    #expect(parseInstant("2026-07-01T11:30:00+02:00") == Date(timeIntervalSince1970: 1_782_898_200))
    #expect(parseInstant("2026-07-01T09:30:00.000Z") == Date(timeIntervalSince1970: 1_782_898_200))
    #expect(parseInstant("yesterday") == nil)
    #expect(formatInstant(Date(timeIntervalSince1970: 1_782_898_200)) == "2026-07-01T09:30:00.000Z")
  }

  @Test func base64URLRoundTrips() {
    let data = Data([0xfb, 0xff, 0x00, 0x10])
    #expect(Base64URL.encode(data) == "-_8AEA")
    #expect(Base64URL.decode("-_8AEA") == data)
    #expect(Base64URL.decode("-_8AEA==") == nil)
  }

  @Test func cacheEntriesAreCodable() throws {
    let entry = CacheEntry(
      body: "{}", etag: "\"e\"", cacheControl: "max-age=30", age: 2,
      receivedAt: Date(timeIntervalSince1970: 0))
    #expect(try JSONDecoder().decode(CacheEntry.self, from: JSONEncoder().encode(entry)) == entry)
    #expect(entry.v == 1)
    #expect(entry.maxAge == 30)
    #expect(entry.isFresh(at: Date(timeIntervalSince1970: 27)))
    #expect(!entry.isFresh(at: Date(timeIntervalSince1970: 28)))
    var noCache = entry
    noCache.cacheControl = "max-age=30, no-cache"
    #expect(!noCache.isFresh(at: Date(timeIntervalSince1970: 1)))
  }

  @Test func allEnumsMapTheirValues() throws {
    func roundTrip<Value: RawRepresentable & Equatable>(_ type: Value.Type, _ raws: [String])
    where Value.RawValue == String {
      for raw in raws + ["something_new"] {
        let value = try! #require(Value(rawValue: raw))
        #expect(value.rawValue == raw)
      }
    }
    roundTrip(EnvironmentKind.self, ["test", "live"])
    roundTrip(Arm.self, ["control", "variant"])
    roundTrip(PlanKind.self, ["plan", "addon"])
    roundTrip(Move.self, ["subscribe", "upgrade", "downgrade", "switch", "add", "replace"])
    roundTrip(MoveAction.self, ["buy", "contact", "unavailable"])
    roundTrip(ChangeEffect.self, ["now", "renewal"])
    roundTrip(BillingMode.self, ["provider", "keep", "end"])
    roundTrip(ChangeTiming.self, ["now", "end"])
    roundTrip(ImpactKind.self, ["gains", "loses", "changes", "same"])
    roundTrip(PriceInterval.self, ["day", "week", "month", "year"])
    roundTrip(TaxBehaviour.self, ["inclusive", "exclusive", "unspecified"])
    roundTrip(PlanStatus.self, ["active", "legacy"])
    roundTrip(TimeUnit.self, ["hours", "days", "weeks", "months"])
    roundTrip(ConnectionMode.self, ["live", "test"])
    roundTrip(Provider.self, ["stripe", "apple", "google"])
    roundTrip(UsageEventKind.self, ["use", "adjust"])
    roundTrip(UsageSource.self, ["api", "client", "dashboard"])
    roundTrip(UsageRefusal.self, ["not_entitled", "over_allowance"])
    roundTrip(UsageMode.self, ["gate", "observe"])
    roundTrip(UsageEventOutcome.self, ["recorded", "duplicate", "error"])
    roundTrip(CustomerKind.self, ["recurring", "one_time", "changing", "default", "none"])
    roundTrip(
      BillingStatus.self,
      [
        "incomplete", "incomplete_expired", "trialing", "active", "past_due", "canceled", "unpaid",
        "paused",
      ])
    roundTrip(TrackSource.self, ["server", "dashboard", "store_sandbox"])
    roundTrip(Money.self, ["real", "test"])
    roundTrip(PaymentStatus.self, ["declined", "requires_action", "processing", "pending"])
    roundTrip(EntitlementSourceType.self, ["plan", "addon", "grant", "banked", "group"])
    roundTrip(
      UsageOutcome.self,
      ["recorded", "duplicate", "refused", "held", "settled", "released", "cancelled", "adjusted"])
    roundTrip(FeatureType.self, ["boolean", "config", "metered", "group"])
  }
}
