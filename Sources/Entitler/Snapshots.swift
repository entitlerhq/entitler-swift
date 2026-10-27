import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

/// A signed snapshot of a customer's entitlements, for an app to keep and verify offline with
/// ``verifySnapshot(_:keys:customer:environment:now:clockSkewSeconds:)``. Its description never
/// shows the token.
public struct Snapshot: Hashable, Sendable, CustomStringConvertible, CustomReflectable {
  /// The signed token. Keep it in the app's own trusted storage.
  public let token: String
  /// The id of the key that signed it.
  public let keyID: String
  /// When it expires.
  public let expiresAt: Date

  /// The key id and expiry, never the token.
  public var description: String { "Snapshot(\(keyID), expires \(expiresAt))" }

  /// The key id and expiry, never the token.
  public var customMirror: Mirror {
    Mirror(self, children: ["keyID": keyID, "expiresAt": expiresAt])
  }
}

/// A public key that verifies snapshots: a P-256 JSON Web Key, kept as Entitler serves it so an
/// app can store it as it is.
public struct SnapshotKey: Codable, Hashable, Sendable {
  /// `EC`.
  public let kty: String
  /// `P-256`.
  public let crv: String
  /// `ES256`.
  public let alg: String
  /// `sig`.
  public let use: String
  /// The key's id.
  public let kid: String
  /// The point's x coordinate, base64url.
  public let x: String
  /// The point's y coordinate, base64url.
  public let y: String
}

/// The public keys that verify snapshots, from ``EntitlerServer/snapshotKeys(timeout:)`` or
/// ``EntitlerClient/snapshotKeys(timeout:)``. Ship them with the build, refresh them when online,
/// and never store them beside the snapshot.
public struct SnapshotKeySet: Codable, Hashable, Sendable {
  /// The keys.
  public let keys: [SnapshotKey]

  /// Creates a set from keys an app kept.
  public init(keys: [SnapshotKey]) { self.keys = keys }
}

/// A snapshot that passed ``verifySnapshot(_:keys:customer:environment:now:clockSkewSeconds:)``.
public struct VerifiedSnapshot: Hashable, Sendable {
  /// The customer's external id.
  public let customer: String
  /// The environment's id.
  public let environment: String
  /// When it was signed.
  public let issuedAt: Date
  /// When it expires.
  public let expiresAt: Date
  /// The customer's entitlements when it was signed, meters included, as
  /// ``Customer/entitlements(asOf:revalidate:timeout:)`` answers them.
  public let entitlements: Entitlements
}

/// A snapshot that did not verify.
public struct SnapshotError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// ``Reason/snapshotInvalid`` or ``Reason/snapshotExpired``.
  public let reason: Reason
  /// What failed.
  public let message: String

  /// The message.
  public var errorDescription: String? { message }

  /// The message.
  public var description: String { message }
}

extension Reason {
  /// The snapshot is malformed, signed by none of the keys passed, or for another customer or
  /// environment.
  public static let snapshotInvalid = Reason(rawValue: "SNAPSHOT_INVALID")
  /// The snapshot has expired.
  public static let snapshotExpired = Reason(rawValue: "SNAPSHOT_EXPIRED")
}

extension Customer {
  /// Signs a snapshot of the customer's entitlements, for the app to keep and verify offline.
  ///
  /// ```swift
  /// let snapshot = try await entitler.me.snapshot(ttlSeconds: 86_400)
  /// try keychain.save(snapshot.token)
  /// ```
  ///
  /// - Parameters:
  ///   - ttlSeconds: How long it lasts, 60 to 2,592,000 seconds, and at most the project's offline
  ///     allowance, which is also the default.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  public func snapshot(ttlSeconds: Int? = nil, timeout: TimeInterval? = nil) async throws
    -> Snapshot
  {
    if let ttlSeconds, !(60...2_592_000).contains(ttlSeconds) {
      throw ArgumentError(message: Messages.snapshotLifetime)
    }
    var request = try Wire.snapshotsCreateSnapshot.request(["external_id": id])
    request.body = try JSONEncoder().encode(ttlSeconds.map { ["lifetimeSeconds": $0] } ?? [:])
    request.retryable = true
    request.timeout = timeout
    return try await core.call(request, decode: decodeSnapshot).answer
  }
}

func snapshotKeys(_ core: Core, timeout: TimeInterval?) async throws -> SnapshotKeySet {
  var request = try Wire.snapshotKeys.request([:])
  request.open = true
  request.timeout = timeout
  return try await core.cachedCall(request) {
    try JSONDecoder().decode(SnapshotKeySet.self, from: $0)
  }
}

func decodeSnapshot(_ body: Data) throws -> Snapshot {
  let answer = try wire(Wire.CreateSnapshotResponse.self, body)
  return Snapshot(token: answer.token, keyID: answer.keyId, expiresAt: date(answer.expiresAt))
}

/// Verifies a snapshot offline, with no request, and answers the entitlements it holds.
///
/// ```swift
/// do {
///   let check = try await entitler.me.check("export_pdf")
/// } catch let error as EntitlerError where error.isUnreachable {
///   let snapshot = try verifySnapshot(
///     token, keys: bundledKeys, customer: session.userID, environment: environmentID)
///   showExport(snapshot.entitlements.has("export_pdf"))
/// }
/// ```
///
/// - Parameters:
///   - token: The snapshot's token, from the app's own trusted storage.
///   - keys: The keys that may have signed it.
///   - customer: The signed-in customer's external id, from the app's own session.
///   - environment: The id of the environment the app ships with.
///   - now: The instant to verify at.
///   - clockSkewSeconds: How far ahead of `now` the signing time may be, 0 to 300 seconds.
/// - Throws: ``EntitlerError/snapshot(_:)`` when it doesn't verify, and ``ArgumentError`` for a
///   skew outside its range.
public func verifySnapshot(
  _ token: String, keys: [SnapshotKey], customer: String, environment: String,
  now: Date = Date(), clockSkewSeconds: Int = 60
) throws -> VerifiedSnapshot {
  guard (0...300).contains(clockSkewSeconds) else {
    throw ArgumentError(message: Messages.clockSkew)
  }
  let parts = token.split(separator: ".", omittingEmptySubsequences: false)
  guard parts.count == 3, let headerData = base64URL(parts[0]),
    let payload = base64URL(parts[1]), let signature = base64URL(parts[2])
  else { throw invalid("The snapshot is not a compact JWS.") }
  guard let header = try? JSONDecoder().decode(Header.self, from: headerData),
    header.alg == "ES256", header.typ == "entitlements+jwt", header.crit == nil
  else { throw invalid("The snapshot's header is not an ES256 entitlements header.") }
  guard
    let key = keys.first(where: {
      $0.kid == header.kid && $0.kty == "EC" && $0.crv == "P-256" && $0.alg == "ES256"
    }),
    let x = base64URL(Substring(key.x)), let y = base64URL(Substring(key.y)),
    let publicKey = try? P256.Signing.PublicKey(rawRepresentation: x + y)
  else { throw invalid("None of the keys passed signed this snapshot.") }
  guard let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature),
    publicKey.isValidSignature(ecdsa, for: Data((parts[0] + "." + parts[1]).utf8))
  else { throw invalid("The snapshot's signature doesn't match its key.") }
  guard let claims = try? JSONDecoder().decode(Claims.self, from: payload) else {
    throw invalid("The snapshot's claims are not entitlement claims.")
  }
  guard claims.iss == "entitler" else { throw invalid("The snapshot was not issued by Entitler.") }
  let instant = now.timeIntervalSince1970
  guard TimeInterval(claims.iat) <= instant + TimeInterval(clockSkewSeconds) else {
    throw invalid("The snapshot was signed in the future.")
  }
  guard instant < TimeInterval(claims.exp) else {
    throw EntitlerError.snapshot(
      SnapshotError(reason: .snapshotExpired, message: "The snapshot has expired."))
  }
  guard claims.sub == customer else { throw invalid("The snapshot is for another customer.") }
  guard claims.environment.id == environment else {
    throw invalid("The snapshot is for another environment.")
  }
  return VerifiedSnapshot(
    customer: claims.sub, environment: claims.environment.id, issuedAt: date(claims.iat),
    expiresAt: date(claims.exp),
    entitlements: Entitlements(
      entitlements: claims.entitlements.map(\.entitlement),
      context: AnswerContext(
        customer: claims.sub, customerID: nil, asOf: date(claims.iat), nextChangeAt: nil,
        served: claims.served)))
}

/// Verifies a snapshot offline against a key set.
public func verifySnapshot(
  _ token: String, keys: SnapshotKeySet, customer: String, environment: String,
  now: Date = Date(), clockSkewSeconds: Int = 60
) throws -> VerifiedSnapshot {
  try verifySnapshot(
    token, keys: keys.keys, customer: customer, environment: environment, now: now,
    clockSkewSeconds: clockSkewSeconds)
}

private func invalid(_ message: String) -> EntitlerError {
  .snapshot(SnapshotError(reason: .snapshotInvalid, message: message))
}

func base64URL(_ text: Substring) -> Data? {
  var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
    of: "_", with: "/")
  base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
  return Data(base64Encoded: base64)
}

private struct Header: Decodable {
  let alg: String
  let typ: String
  let kid: String
  let crit: ClaimValue?
}

private struct Named: Decodable {
  let id: String
}

private struct Claims: Decodable {
  struct Track: Decodable {
    let id: String
    let name: String
  }

  struct Release: Decodable {
    let id: String
    let number: Int64
  }

  let iss: String
  let sub: String
  let environment: Named
  let track: Track?
  let release: Release?
  let change: Named?
  let entitlements: [ClaimEntitlement]
  let iat: Int64
  let exp: Int64

  var served: Served {
    let track = track.map { ServedTrack(id: $0.id, name: $0.name) }
    if let release {
      return Served(track: track, source: .release(id: release.id, number: release.number))
    }
    if let change { return Served(track: track, source: .change(id: change.id)) }
    return Served(track: track, source: .nothing)
  }
}

private enum ClaimValue: Decodable {
  case on(Bool)
  case amount(Int64)
  case unlimited
  case list(markets: [String: Limit]?)
  case other

  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let on = try? value.decode(Bool.self) {
      self = .on(on)
    } else if let amount = try? value.decode(Int64.self) {
      self = .amount(amount)
    } else if (try? value.decode(String.self)) == "unlimited" {
      self = .unlimited
    } else if let markets = try? value.decode([MarketClaim].self) {
      self = .list(
        markets: Dictionary(
          markets.compactMap { claim in claim.limit.limit.map { (claim.marketId, $0) } }
        ) {
          _, last in last
        })
    } else if (try? value.decode([ClaimValue].self)) != nil {
      self = .list(markets: nil)
    } else {
      self = .other
    }
  }

  var limit: Limit? {
    switch self {
    case .amount(let amount): .amount(amount)
    case .unlimited: .unlimited
    default: nil
    }
  }

  func feature(entitled: Bool, type: FeatureType) -> FeatureValue {
    switch self {
    case .on(let on): on ? .on : .amount(0)
    case .amount(let amount): .amount(amount)
    case .unlimited: .unlimited
    case .list: type == .group && entitled ? .on : .amount(0)
    case .other: .amount(0)
    }
  }

  func markets(type: FeatureType) -> [String: Limit]? {
    guard type != .group, case .list(let markets) = self else { return nil }
    return markets ?? [:]
  }
}

private struct MarketClaim: Decodable {
  let marketId: String
  let limit: ClaimValue
}

private struct ClaimEntitlement: Decodable {
  let key: String
  let kind: String
  let entitled: Bool
  let value: ClaimValue?
  let sources: [ClaimSource]?
  let used: Int64?
  let held: Int64?
  let banked: Int64?
  let remaining: ClaimValue?
  let resetsAt: Int64?
  let decimals: Int?
  let currency: String?

  var entitlement: Entitlement {
    let type = FeatureType(rawValue: kind)
    return Entitlement(
      key: key, type: type, entitled: entitled,
      value: value?.feature(entitled: entitled, type: type) ?? .amount(0),
      markets: value?.markets(type: type),
      decimals: decimals ?? 0, currency: currency.flatMap { $0.isEmpty ? nil : $0 },
      sources: (sources ?? []).compactMap { $0.source(of: type) }, upgrades: [],
      meter: type == .metered
        ? Meter(
          used: used ?? 0, held: held ?? 0, banked: banked ?? 0,
          remaining: remaining?.limit ?? .amount(0), resetsAt: resetsAt.map(date))
        : nil)
  }
}

private struct ClaimSource: Decodable {
  struct Plan: Decodable {
    let id: String
    let key: String
    let name: String
  }

  let type: String
  let plan: Plan?
  let version: Int64?
  let product: String?
  let value: ClaimValue?
  let through: String?
  let quantity: Int64?
  let grant: String?
  let until: Int64?
  let features: [String]?

  func source(of feature: FeatureType) -> EntitlementSource? {
    let markets = value?.markets(type: feature)
    let value = value?.feature(entitled: true, type: feature)
    let through = through.flatMap { $0.isEmpty ? nil : $0 }
    switch type {
    case "plan", "default_plan":
      guard let plan, let version else { return nil }
      let byDefault = type == "default_plan"
      return .plan(
        PlanSource(
          planID: plan.id, plan: plan.key, name: plan.name, product: product, version: version,
          byDefault: byDefault, value: byDefault ? nil : value,
          markets: byDefault ? nil : markets, through: through))
    case "add_on":
      guard let plan, let version, let quantity else { return nil }
      return .addOn(
        AddOnSource(
          planID: plan.id, plan: plan.key, name: plan.name, version: version, quantity: quantity,
          value: value, markets: markets, through: through))
    case "grant":
      guard let grant else { return nil }
      return .grant(
        GrantSource(
          grant: grant, until: until.map(date), value: value, markets: markets, through: through))
    case "group":
      return .group(features: features ?? [])
    default:
      return nil
    }
  }
}
