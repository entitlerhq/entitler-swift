import Foundation
import Testing

@testable import Entitler

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let signingKey = P256.Signing.PrivateKey()

let snapshotKey = SnapshotKey(
  kty: "EC", crv: "P-256", alg: "ES256", use: "sig", kid: "sk_1",
  x: base64URL(signingKey.publicKey.rawRepresentation.prefix(32)),
  y: base64URL(signingKey.publicKey.rawRepresentation.suffix(32)))

let issued = Date(timeIntervalSince1970: 1_790_000_000)

func base64URL(_ data: Data) -> String {
  data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func signed(
  _ claims: [String: Any] = [:], header: [String: Any] = [:],
  key: P256.Signing.PrivateKey = signingKey
) throws -> String {
  let fullHeader = ["alg": "ES256", "typ": "entitlements+jwt", "kid": "sk_1"].merging(header) { $1 }
  let fullClaims: [String: Any] = [
    "iss": "entitler", "sub": "ada", "environment": ["id": "en_1"], "entitlements": [],
    "iat": 1_790_000_000, "exp": 1_790_086_400,
  ].merging(claims) { $1 }
  let signingInput =
    base64URL(try JSONSerialization.data(withJSONObject: fullHeader)) + "."
    + base64URL(try JSONSerialization.data(withJSONObject: fullClaims))
  let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
  return signingInput + "." + base64URL(signature)
}

func verified(_ token: String, now: Date = issued) throws -> VerifiedSnapshot {
  try verifySnapshot(token, keys: [snapshotKey], customer: "ada", environment: "en_1", now: now)
}

func refusedReason(_ token: String, now: Date = issued) -> Reason? {
  do {
    _ = try verified(token, now: now)
  } catch EntitlerError.snapshot(let error) {
    return error.reason
  } catch {}
  return nil
}

@Suite struct SnapshotTests {
  @Test func snapshotPostsItsLifetimeAndHidesTheToken() async throws {
    let api = FakeAPI([
      Answer(body: #"{"token": "eyJ.secret.sig", "keyId": "sk_1", "expiresAt": 1790086400}"#)
    ])
    let snapshot = try await api.server().customer("ada").snapshot(ttlSeconds: 86_400)

    let request = try #require(api.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/v1/customers/ada/snapshots")
    #expect(body(request)["lifetimeSeconds"] as? Int == 86_400)
    #expect(snapshot.keyID == "sk_1")
    #expect(snapshot.expiresAt == Date(timeIntervalSince1970: 1_790_086_400))
    #expect(!"\(snapshot)".contains("secret"))
    #expect(!String(reflecting: snapshot).contains("secret"))
  }

  @Test func snapshotLeavesTheLifetimeToTheProjectAndRefusesOneOutOfRange() async throws {
    let api = FakeAPI([Answer(body: #"{"token": "t", "keyId": "sk_1", "expiresAt": 1}"#)])
    let customer = try api.server().customer("ada")
    _ = try await customer.snapshot()
    #expect(body(try #require(api.requests.first)).isEmpty)
    await #expect(throws: ArgumentError.self) { try await customer.snapshot(ttlSeconds: 59) }
    await #expect(throws: ArgumentError.self) { try await customer.snapshot(ttlSeconds: 2_592_001) }
  }

  @Test func snapshotKeysAreFetchedWithNoCredentialAndKept() async throws {
    let keys =
      #"{"keys": [{"kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig", "kid": "sk_1", "x": "AA", "y": "AQ"}]}"#
    let api = FakeAPI([Answer(headers: ["Cache-Control": "public, max-age=3600"], body: keys)])
    let entitler = try client(api, Tokens([]))
    let first = try await entitler.snapshotKeys()
    let second = try await entitler.snapshotKeys()

    #expect(first == second)
    #expect(first.keys.map(\.kid) == ["sk_1"])
    let request = try #require(api.requests.first)
    #expect(request.url?.path == "/v1/snapshot-keys")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(api.requests.count == 1)
  }

  @Test func aVerifiedSnapshotAnswersItsEntitlements() throws {
    let token = try signed([
      "track": ["id": "tr_1", "name": "All customers"],
      "release": ["id": "re_1", "number": 12],
      "entitlements": [
        [
          "key": "priority_support", "kind": "switch", "entitled": true, "value": true,
          "sources": [
            [
              "type": "plan", "plan": ["id": "pl_1", "key": "pro", "name": "Pro"], "version": 3,
              "product": "pr_1", "value": true,
            ],
            ["type": "grant", "grant": "gr_1", "until": 1_790_086_400],
            ["type": "coupon"],
          ],
        ],
        [
          "key": "api_calls", "kind": "metered", "entitled": true, "value": 1000, "used": 400,
          "held": 50, "banked": 0, "remaining": 550, "resetsAt": 1_792_000_000, "decimals": 2,
          "currency": "aud",
          "sources": [
            [
              "type": "addon", "plan": ["id": "pl_9", "key": "boost", "name": "Boost"],
              "version": 1, "quantity": 2, "value": 500, "through": "",
            ],
            [
              "type": "default_plan", "plan": ["id": "pl_0", "key": "free", "name": "Free"],
              "version": 1,
            ],
          ],
        ],
        ["key": "exports", "kind": "metered", "entitled": false, "value": 0],
        ["key": "seats", "kind": "configuration", "entitled": true, "value": "unlimited"],
        [
          "key": "workspace", "kind": "group", "entitled": true, "value": ["seats"],
          "sources": [["type": "group", "features": ["seats"]]],
        ],
      ],
    ])
    let snapshot = try verified(token)
    let entitlements = snapshot.entitlements

    #expect(snapshot.customer == "ada")
    #expect(snapshot.expiresAt == Date(timeIntervalSince1970: 1_790_086_400))
    #expect(entitlements.asOf == issued)
    #expect(entitlements.customerID == nil)
    #expect(entitlements.served.source == .release(id: "re_1", number: 12))
    #expect(entitlements.served.track?.name == "All customers")

    let support = try #require(entitlements["priority_support"])
    #expect(support.type == .switch)
    #expect(support.value == .on)
    #expect(support.meter == nil)
    #expect(support.decimals == 0)
    #expect(support.currency == nil)
    #expect(support.sources.count == 2)
    guard case .plan(let plan) = support.sources[0], case .grant(let grant) = support.sources[1]
    else { throw SourceMismatch() }
    #expect(plan.product == "pr_1")
    #expect(plan.value == .on)
    #expect(grant.until == Date(timeIntervalSince1970: 1_790_086_400))

    let calls = try #require(entitlements["api_calls"])
    #expect(calls.value == .amount(1000))
    #expect(calls.decimals == 2)
    #expect(calls.currency == "aud")
    #expect(calls.markets == nil)
    #expect(
      calls.meter
        == Meter(
          used: 400, held: 50, banked: 0, remaining: .amount(550),
          resetsAt: Date(timeIntervalSince1970: 1_792_000_000)))
    guard case .addOn(let addOn) = calls.sources[0], case .plan(let free) = calls.sources[1]
    else { throw SourceMismatch() }
    #expect(addOn.quantity == 2)
    #expect(addOn.through == nil)
    #expect(free.byDefault)

    #expect(
      entitlements["exports"]?.meter
        == Meter(used: 0, held: 0, banked: 0, remaining: .amount(0), resetsAt: nil))
    #expect(entitlements["seats"]?.value == .unlimited)
    #expect(entitlements["workspace"]?.value == .on)
    #expect(entitlements["workspace"]?.sources == [.group(features: ["seats"])])
    #expect(entitlements.has("workspace"))
  }

  @Test func anExpiredSnapshotIsRefusedAsExpiredAndNeverUnreachable() throws {
    let token = try signed()
    do {
      _ = try verified(token, now: Date(timeIntervalSince1970: 1_790_086_400))
      Issue.record("Expected an expired snapshot.")
    } catch let error as EntitlerError {
      guard case .snapshot(let snapshot) = error else { throw error }
      #expect(snapshot.reason == .snapshotExpired)
      #expect(!error.isUnreachable)
    }
  }

  @Test func aSnapshotThatDoesNotMatchIsRefusedAsInvalid() throws {
    let token = try signed()
    let parts = token.split(separator: ".")
    let otherClaims = try signed(["sub": "grace"]).split(separator: ".")[1]

    #expect(refusedReason(try signed(["sub": "grace"])) == .snapshotInvalid)
    #expect(refusedReason(try signed(["environment": ["id": "en_2"]])) == .snapshotInvalid)
    #expect(refusedReason(try signed(["iss": "someone"])) == .snapshotInvalid)
    #expect(refusedReason(try signed(["iat": 1_790_000_061])) == .snapshotInvalid)
    #expect(refusedReason(try signed(header: ["kid": "sk_2"])) == .snapshotInvalid)
    #expect(refusedReason(try signed(header: ["typ": "JWT"])) == .snapshotInvalid)
    #expect(refusedReason(try signed(header: ["crit": ["exp"]])) == .snapshotInvalid)
    #expect(refusedReason(try signed(key: P256.Signing.PrivateKey())) == .snapshotInvalid)
    #expect(refusedReason("\(parts[0]).\(otherClaims).\(parts[2])") == .snapshotInvalid)
    #expect(refusedReason("not.a-token") == .snapshotInvalid)
    #expect(refusedReason(try signed(["iat": 1_790_000_060])) == nil)
  }

  @Test func aSkewOutOfRangeIsRefused() throws {
    let token = try signed()
    #expect(throws: ArgumentError.self) {
      try verifySnapshot(
        token, keys: SnapshotKeySet(keys: [snapshotKey]), customer: "ada", environment: "en_1",
        clockSkewSeconds: 301)
    }
  }
}

struct SourceMismatch: Error {}
