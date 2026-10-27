import Foundation

/// Who made a change.
public struct ChangedBy: Hashable, Sendable {
  /// `user` for a dashboard user, `key` for an API key, `system` for Entitler.
  public let type: OpenName
  /// The user's or key's id.
  public let id: String
}

/// A grant: a feature value given to one customer outside their plans, for a while or for good.
public struct Grant: Hashable, Sendable {
  /// The grant's id.
  public let id: String
  /// The feature's key.
  public let feature: String
  /// ``FeatureValue/on`` for an on/off feature, else the amount granted in the feature's smallest
  /// unit, or ``FeatureValue/unlimited``.
  public let value: FeatureValue
  /// When the grant started.
  public let from: Date
  /// When it ends, or `nil` when it lasts until revoked.
  public let until: Date?
  /// Why it was given; empty when no reason was given.
  public let reason: String
  /// When it was revoked, or `nil`.
  public let revokedAt: Date?
  /// Why it was revoked, or `nil`.
  public let revokeReason: String?
  /// Who gave it, or `nil` when Entitler doesn't know.
  public let grantedBy: ChangedBy?
  /// Who revoked it, or `nil`.
  public let revokedBy: ChangedBy?
}

/// The answer to ``ServerCustomer/grant(_:value:days:reason:expectedRevision:currency:timeout:)``.
public struct GrantResult: Hashable, Sendable {
  /// The grant.
  public let grant: Grant
  /// The customer's revision after it, to pass as the next write's `expectedRevision`.
  public let revision: Int64
}

/// The answer to ``ServerCustomer/revokeGrant(_:reason:expectedRevision:timeout:)``.
public struct RevokedGrant: Hashable, Sendable {
  /// The grant.
  public let grant: Grant
  /// The customer's revision after it.
  public let revision: Int64
  /// False when the grant was revoked already, so this call changed nothing.
  public let changed: Bool
}

/// The answer to ``ServerCustomer/setTrack(_:timeout:)``: the customer's track now, and what moving
/// them did.
public struct TrackAssignment: Hashable, Sendable {
  /// The id of the track the customer is on now, or `nil` for the default track.
  public let track: String?
  /// The id of the track they were on before, or `nil` for the default track.
  public let previousTrack: String?
  /// Who set the track last: `server` for the API, `dashboard` for the dashboard.
  public let source: OpenName
  /// `real` for a customer who pays real money, `test` for one in test mode.
  public let money: OpenName
  /// The customer's revision after the change.
  public let revision: Int64
  /// False when the customer was on that track already, so this call changed nothing.
  public let changed: Bool
  /// How many test subscriptions and add-ons moving the customer ended.
  public let endedTestHoldings: Int64
}

/// How to adjust a meter.
public enum MeterAdjustment: Hashable, Sendable {
  /// Sets what is used to an amount of 0 or more.
  case setTo(Int64)
  /// Moves what is used by an amount, below 0 to give some back.
  case changeBy(Int64)
}

extension ServerCustomer {
  /// Gives the customer a feature value outside their plans. Never retried, since a retry could
  /// grant twice.
  ///
  /// ```swift
  /// try await customer.grant("ai_credits", value: .amount(5_000), days: 30, reason: "Ticket 4127")
  /// ```
  ///
  /// - Parameters:
  ///   - value: ``FeatureValue/on`` for an on/off feature; for a metered or configuration
  ///     feature, an amount of 0 or more in the feature's smallest unit, or
  ///     ``FeatureValue/unlimited``.
  ///   - days: How many days it lasts, 1 to 3,650. Leave it out for a grant that lasts until
  ///     revoked.
  ///   - reason: Why, kept with the grant and shown in the dashboard.
  ///   - expectedRevision: The customer's revision this was decided on. When the record has
  ///     changed since, the write fails with an ``APIError`` and changes nothing.
  ///   - currency: The customer's lower-case currency code, for a money feature.
  public func grant(
    _ feature: String, value: FeatureValue, days: Int? = nil, reason: String? = nil,
    expectedRevision: Int64? = nil, currency: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> GrantResult {
    if let days, !(1...3650).contains(days) { throw ArgumentError(message: Messages.grantDays) }
    let body = GrantBody(
      featureKey: try require(feature, Messages.feature), value: try grantValue(value),
      days: days, reason: reason, expectedRevision: try revision(expectedRevision),
      currency: currency)
    return try await companyWrite(
      Wire.grantsCreateGrant, [:], body, retryable: false, timeout, decodeGrant)
  }

  /// Gives the customer a value of a declared feature outside their plans.
  public func grant<Kind>(
    _ feature: Feature<Kind>, value: FeatureValue, days: Int? = nil, reason: String? = nil,
    expectedRevision: Int64? = nil, currency: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> GrantResult {
    try await grant(
      feature.key, value: value, days: days, reason: reason, expectedRevision: expectedRevision,
      currency: currency, timeout: timeout)
  }

  /// Ends a grant now. Revoking twice is safe: the second answers `changed` false. Retried only
  /// without `expectedRevision`, since the first revocation moves the revision on.
  @discardableResult
  public func revokeGrant(
    _ id: String, reason: String? = nil, expectedRevision: Int64? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> RevokedGrant {
    try await companyWrite(
      Wire.grantsRevokeGrant, ["grant_id": try require(id, Messages.grant)],
      RevisionBody(reason: reason, expectedRevision: try revision(expectedRevision)),
      retryable: expectedRevision == nil, timeout, decodeRevokedGrant)
  }

  /// Moves the customer to a track, or back to the default track with `nil`.
  @discardableResult
  public func setTrack(_ id: String?, timeout: TimeInterval? = nil) async throws
    -> TrackAssignment
  {
    try await companyWrite(
      Wire.customerTracksAssignTrack, [:],
      TrackBody(trackId: try id.map { try require($0, Messages.track) }), retryable: true,
      timeout, decodeTrack)
  }

  /// Sets or moves what the customer has used of a metered feature, outside any usage report.
  /// Retried only with an `idempotencyKey`.
  ///
  /// - Parameters:
  ///   - idempotencyKey: A key naming the adjustment in your own system, so a retry never adjusts
  ///     twice.
  ///   - currency: The customer's lower-case currency code, for a money feature.
  /// - Returns: The answer, with outcome `adjusted`.
  @discardableResult
  public func adjustMeter(
    of feature: Feature<Metered>, _ adjustment: MeterAdjustment, reason: String? = nil,
    idempotencyKey: String? = nil, currency: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await adjustMeter(
      of: feature.key, adjustment, reason: reason, idempotencyKey: idempotencyKey,
      currency: currency, timeout: timeout)
  }

  /// Sets or moves what the customer has used of a metered feature named by its key.
  @discardableResult
  public func adjustMeter(
    of feature: String, _ adjustment: MeterAdjustment, reason: String? = nil,
    idempotencyKey: String? = nil, currency: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    var body = AdjustBody(
      reason: reason, idempotencyKey: try idempotencyKey.map { try validIdempotencyKey($0) },
      currency: currency)
    switch adjustment {
    case .setTo(let amount):
      guard amount >= 0 else { throw ArgumentError(message: Messages.setTo) }
      body.setTo = amount
    case .changeBy(let amount):
      body.changeBy = amount
    }
    return try await companyWrite(
      Wire.usageAdjustMeter, ["feature_key": try require(feature, Messages.feature)], body,
      idempotencyKey: body.idempotencyKey, retryable: body.idempotencyKey != nil, timeout,
      decodeUsage)
  }

  /// Cancels a usage report, giving back what it used.
  ///
  /// - Returns: The answer, with outcome `cancelled`.
  @discardableResult
  public func cancelUsage(_ id: String, reason: String? = nil, timeout: TimeInterval? = nil)
    async throws -> UsageResult
  {
    try await companyWrite(
      Wire.usageCancelReport, ["usage_id": try require(id, Messages.usageReport)],
      RevisionBody(reason: reason), retryable: true, timeout, decodeUsage)
  }

  private func companyWrite<Body: Encodable, Answer: Sendable>(
    _ route: Route, _ variables: [String: String], _ body: Body, idempotencyKey: String? = nil,
    retryable: Bool, _ timeout: TimeInterval?,
    _ decode: @escaping @Sendable (Data) throws -> Answer
  ) async throws -> Answer {
    var request = try route.request(variables.merging(["external_id": id]) { $1 })
    request.body = try JSONEncoder().encode(body)
    request.idempotencyKey = idempotencyKey
    request.retryable = retryable
    request.timeout = timeout
    return try await core.call(request, decode: decode).answer
  }
}

private struct Revision: Encodable {
  var value: Int64
}

private struct GrantBody: Encodable {
  var featureKey: String
  var value: GrantValueBody
  var days: Int?
  var reason: String?
  var expectedRevision: Revision?
  var currency: String?
}

private struct GrantValueBody: Encodable {
  struct LimitBody: Encodable {
    var count: Int64?
    var unlimited: [String: String]?
  }

  var on: [String: String]?
  var limit: LimitBody?
}

private struct RevisionBody: Encodable {
  var reason: String?
  var expectedRevision: Revision?
}

private struct TrackBody: Encodable {
  var trackId: String?
}

private struct AdjustBody: Encodable {
  var setTo: Int64?
  var changeBy: Int64?
  var reason: String?
  var idempotencyKey: String?
  var currency: String?
}

private func grantValue(_ value: FeatureValue) throws -> GrantValueBody {
  switch value {
  case .on: return GrantValueBody(on: [:])
  case .unlimited: return GrantValueBody(limit: .init(unlimited: [:]))
  case .amount(let count):
    guard count >= 0 else { throw ArgumentError(message: Messages.grantValue) }
    return GrantValueBody(limit: .init(count: count))
  }
}

private func revision(_ value: Int64?) throws -> Revision? {
  guard let value else { return nil }
  guard value >= 0 else { throw ArgumentError(message: Messages.expectedRevision) }
  return Revision(value: value)
}

private func changedBy(_ value: Wire.Actor?) -> ChangedBy? {
  value.map { ChangedBy(type: openName($0.type, prefix: "ACTOR_TYPE_"), id: $0.id) }
}

private func grantedValue(_ value: Wire.GrantValue?) throws -> FeatureValue {
  let value = try given(value)
  if value.on != nil { return .on }
  return amount(limit(try at("limit") { try given(value.limit) }))
}

private func grant(_ value: Wire.Grant) throws -> Grant {
  Grant(
    id: value.id, feature: value.featureKey,
    value: try at("value") { try grantedValue(value.value) },
    from: date(value.from),
    until: value.until.map(date), reason: value.reason, revokedAt: value.revokedAt.map(date),
    revokeReason: value.revokeReason, grantedBy: changedBy(value.grantedBy),
    revokedBy: changedBy(value.revokedBy))
}

func decodeGrant(_ body: Data) throws -> GrantResult {
  let answer = try wire(Wire.CreateGrantResponse.self, body)
  return GrantResult(
    grant: try at("grant") { try grant(try given(answer.grant)) }, revision: answer.revision)
}

func decodeRevokedGrant(_ body: Data) throws -> RevokedGrant {
  let answer = try wire(Wire.RevokeGrantResponse.self, body)
  return RevokedGrant(
    grant: try at("grant") { try grant(try given(answer.grant)) }, revision: answer.revision,
    changed: answer.changed)
}

func decodeTrack(_ body: Data) throws -> TrackAssignment {
  let answer = try wire(Wire.AssignTrackResponse.self, body)
  let assignment = try at("assignment") { try given(answer.assignment) }
  return TrackAssignment(
    track: assignment.trackId, previousTrack: assignment.previousTrackId,
    source: openName(assignment.source, prefix: "ASSIGNMENT_SOURCE_"),
    money: openName(assignment.money, prefix: "CUSTOMER_MONEY_"), revision: assignment.revision,
    changed: answer.changed, endedTestHoldings: answer.endedTestHoldings)
}
