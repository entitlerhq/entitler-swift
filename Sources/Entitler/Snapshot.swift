import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

/// A public key that verifies snapshots, from ``EntitlerServer/snapshotKeys(timeout:)``.
public struct JSONWebKey: Codable, Hashable, Sendable {
  /// The key type, `EC`.
  public let kty: String
  /// The curve, `P-256`.
  public let crv: String
  /// The x coordinate, base64url.
  public let x: String
  /// The y coordinate, base64url.
  public let y: String
  /// The key's id.
  public let kid: String
  /// The algorithm, `ES256`.
  public let alg: String
  /// The use, `sig`.
  public let use: String
}

/// The keys that verify snapshots, as a JSON Web Key Set.
public struct JSONWebKeySet: Codable, Hashable, Sendable {
  /// The keys.
  public let keys: [JSONWebKey]
}

/// What a snapshot must be to pass ``verifySnapshot(_:expecting:)``.
///
/// The keys decide which snapshots an app trusts. Ship them with the app (from `snapshotKeys()`
/// at build time) and replace them only with keys fetched from Entitler over HTTPS. Never store
/// them beside the token or load them from the same record: anyone who can edit that record could
/// replace both.
public struct SnapshotExpectation: Sendable {
  /// The keys that may have signed it.
  public var keys: [JSONWebKey]
  /// The customer's external id it must be for.
  public var customer: String
  /// The environment id it must be from.
  public var environment: String
  /// The issuer it must name.
  public var issuer: String
  /// The instant to verify at; `nil` for the system clock.
  public var now: Date?
  /// How far the snapshot's `iat` may be ahead of now, 0 to 300 seconds.
  public var clockSkewSeconds: Int

  /// Creates an expectation from a list of keys.
  public init(
    keys: [JSONWebKey], customer: String, environment: String,
    issuer: String = "https://api.entitler.dev/customers", now: Date? = nil,
    clockSkewSeconds: Int = 60
  ) {
    self.keys = keys
    self.customer = customer
    self.environment = environment
    self.issuer = issuer
    self.now = now
    self.clockSkewSeconds = clockSkewSeconds
  }

  /// Creates an expectation from a key set.
  public init(
    keys: JSONWebKeySet, customer: String, environment: String,
    issuer: String = "https://api.entitler.dev/customers", now: Date? = nil,
    clockSkewSeconds: Int = 60
  ) {
    self.init(
      keys: keys.keys, customer: customer, environment: environment, issuer: issuer, now: now,
      clockSkewSeconds: clockSkewSeconds)
  }
}

/// The environment a snapshot is from.
public struct SnapshotEnvironment: Codable, Hashable, Sendable {
  /// The environment's id.
  public let id: String
}

/// A verified snapshot: the customer's entitlements as Entitler signed them.
///
/// Meters are frozen at the instant it was signed.
public struct VerifiedSnapshot: Hashable, Sendable {
  /// The customer's external id.
  public let customer: String
  /// The environment it is from.
  public let environment: SnapshotEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track served, or `nil` when it followed a change.
  public let release: Int64?
  /// The change the track followed, or `nil` when it served a release.
  public let change: String?
  /// Whether test money is taken.
  public let testers: Bool
  /// When it expires.
  public let expiresAt: Date
  /// The entitlements, with Entitler's decision on each and groups included.
  public let entitlements: Entitlements
}

private struct SnapshotHeader: Decodable {
  let typ: String
  let alg: String
  let kid: String
}

private struct SnapshotClaims: Decodable {
  let iss: String
  let sub: String
  let environment: SnapshotEnvironment
  let track: Track
  let release: Int64?
  let change: String?
  let testers: Bool
  let entitlements: [Entitlement]
  let iat: Int64
  let exp: Int64
}

/// Verifies an offline snapshot from ``Customer/snapshot(ttlSeconds:idempotencyKey:timeout:)`` with no request.
///
/// ```swift
/// let snapshot = try verifySnapshot(token, expecting: SnapshotExpectation(
///   keys: bundledKeys, customer: "user_123", environment: environmentID))
/// if snapshot.entitlements.has(Features.exportPDF) { … }
/// ```
///
/// - Throws: ``EntitlerError/snapshot(_:)`` when it fails a check, and ``ArgumentError`` when
///   `clockSkewSeconds` is outside 0 to 300.
public func verifySnapshot(_ token: String, expecting expected: SnapshotExpectation) throws
  -> VerifiedSnapshot
{
  guard (0...300).contains(expected.clockSkewSeconds) else {
    throw ArgumentError(message: "Pass clockSkewSeconds as a whole number from 0 to 300.")
  }
  func fail(_ code: SnapshotError.Code = .invalid, _ message: String) -> EntitlerError {
    .snapshot(SnapshotError(code: code, message: message))
  }
  let malformed = fail(
    .invalid, "That is not an entitlements snapshot. Pass the token snapshot() returned.")
  let segments = token.split(separator: ".", omittingEmptySubsequences: false)
  guard segments.count == 3,
    let headerData = Base64URL.decode(segments[0]),
    let signature = Base64URL.decode(segments[2]),
    let header = try? JSON.decoder().decode(SnapshotHeader.self, from: headerData),
    header.typ == "entitlements+jwt", header.alg == "ES256",
    let fields = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
    fields["crit"] == nil
  else { throw malformed }

  guard let key = expected.keys.first(where: { $0.kid == header.kid }) else {
    throw fail(
      .invalid,
      "None of the keys passed signed this snapshot. Fetch them again with snapshotKeys().")
  }
  let changed = fail(.invalid, "This snapshot was changed after Entitler signed it.")
  guard let x = Base64URL.decode(key.x), let y = Base64URL.decode(key.y),
    let publicKey = try? P256.Signing.PublicKey(rawRepresentation: x + y),
    let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature),
    publicKey.isValidSignature(ecdsa, for: Data("\(segments[0]).\(segments[1])".utf8))
  else { throw changed }

  guard let payload = Base64URL.decode(segments[1]),
    let claims = try? JSON.decoder().decode(SnapshotClaims.self, from: payload)
  else { throw malformed }
  guard claims.iss == expected.issuer else {
    throw fail(.invalid, "This snapshot was not issued by \(expected.issuer).")
  }
  let now = expected.now ?? Hooks.current.now()
  let instants = -62_135_596_800...253_402_300_799 as ClosedRange<Int64>
  guard instants.contains(claims.iat), instants.contains(claims.exp) else { throw malformed }
  let issuedAt = Date(timeIntervalSince1970: TimeInterval(claims.iat))
  let expiresAt = Date(timeIntervalSince1970: TimeInterval(claims.exp))
  guard issuedAt <= now.addingTimeInterval(TimeInterval(expected.clockSkewSeconds)) else {
    throw fail(
      .invalid,
      "This snapshot was signed for \(formatInstant(issuedAt)), which is still to come. Fetch a new one while online."
    )
  }
  guard now < expiresAt else {
    throw fail(
      .expired,
      "This snapshot expired at \(formatInstant(expiresAt)). Fetch a new one while online.")
  }
  guard claims.sub == expected.customer else {
    throw fail(
      .invalid,
      "This snapshot is for another customer, not \(expected.customer). Fetch one for the signed-in customer while online."
    )
  }
  guard claims.environment.id == expected.environment else {
    throw fail(
      .invalid,
      "This snapshot is from another environment, not \(expected.environment). Fetch one from your app's environment while online."
    )
  }
  return VerifiedSnapshot(
    customer: claims.sub, environment: claims.environment, track: claims.track,
    release: claims.release, change: claims.change, testers: claims.testers, expiresAt: expiresAt,
    entitlements: Entitlements(
      customer: claims.sub, asOf: issuedAt, items: claims.entitlements,
      environment: nil,
      track: claims.track, release: claims.release, change: claims.change, testers: claims.testers,
      experiment: nil))
}
