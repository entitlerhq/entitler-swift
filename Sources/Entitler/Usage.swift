import Foundation

/// How a usage report counts against the allowance, extensible: a mode this SDK does not list is
/// kept as it is.
public struct UsageMode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The mode as the SDK spells it, such as `observe`.
  public let rawValue: String

  /// Creates a mode from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The mode's spelling.
  public var description: String { rawValue }

  /// Records only what fits the allowance, and refuses the rest.
  public static let gate = UsageMode(rawValue: "gate")
  /// Records everything, and says in ``UsageResult/overBy`` how far past the allowance it is.
  public static let observe = UsageMode(rawValue: "observe")
}

/// What a usage write did, extensible: an outcome this SDK does not list is kept as it is.
public struct UsageOutcome: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The outcome as the SDK spells it, such as `recorded`.
  public let rawValue: String

  /// Creates an outcome from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The outcome's spelling.
  public var description: String { rawValue }

  /// The usage was recorded.
  public static let recorded = UsageOutcome(rawValue: "recorded")
  /// A gated report or a hold did not fit; ``UsageResult/refusal`` says why.
  public static let refused = UsageOutcome(rawValue: "refused")
  /// The idempotency key repeated a request still in progress or already answered.
  public static let duplicate = UsageOutcome(rawValue: "duplicate")
  /// The report was cancelled.
  public static let cancelled = UsageOutcome(rawValue: "cancelled")
  /// The amount is held.
  public static let held = UsageOutcome(rawValue: "held")
  /// The hold was settled.
  public static let settled = UsageOutcome(rawValue: "settled")
  /// The hold was released, recording nothing.
  public static let released = UsageOutcome(rawValue: "released")
  /// The meter was adjusted.
  public static let adjusted = UsageOutcome(rawValue: "adjusted")
}

/// Why a gated report or a hold was refused, extensible: a refusal this SDK does not list is kept
/// as it is.
public struct UsageRefusal: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The refusal as the SDK spells it, such as `over_allowance`.
  public let rawValue: String

  /// Creates a refusal from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The refusal's spelling.
  public var description: String { rawValue }

  /// The customer is not entitled to the feature.
  public static let notEntitled = UsageRefusal(rawValue: "not_entitled")
  /// The amount does not fit what is left.
  public static let overAllowance = UsageRefusal(rawValue: "over_allowance")
}

/// The answer to a usage write: the feature's entitlement after it, and what the write did. Read
/// the entitlement's fields straight from it, such as `result.meter`.
@dynamicMemberLookup
public struct UsageResult: Hashable, Sendable {
  /// The feature's entitlement after the write.
  public let entitlement: Entitlement
  /// Where the answer comes from, and for whom.
  public let context: AnswerContext
  /// What happened.
  public let outcome: UsageOutcome
  /// Why a gated report or a hold was refused, else `nil`.
  public let refusal: UsageRefusal?
  /// The usage report this created, repeated or settled, or `nil`.
  public let id: String?
  /// The hold this created, settled, released or repeated, or `nil`.
  public let holdID: String?
  /// The report's mode.
  public let mode: UsageMode
  /// The amount asked for, or the first request's on a replay.
  public let amount: Int64
  /// How much this request moved the meter.
  public let meterChange: Int64
  /// How far use is past the allowance after the write; `0` within it.
  public let overBy: Int64
  /// True when the report's period had closed when it arrived, so it moved no meter.
  public let late: Bool
  /// When the usage happened, or `nil`.
  public let occurredAt: Date?
  /// When the hold expires, or `nil` for a report.
  public let expiresAt: Date?
  /// True when the idempotency key repeated an earlier request, which answered this.
  public let replayed: Bool

  /// Reads a field of ``entitlement``.
  public subscript<Value>(dynamicMember field: KeyPath<Entitlement, Value>) -> Value {
    entitlement[keyPath: field]
  }

  /// Reads a field of ``context``.
  public subscript<Value>(dynamicMember field: KeyPath<AnswerContext, Value>) -> Value {
    context[keyPath: field]
  }
}

/// An open hold, from ``Customer/startHold(of:amount:idempotencyKey:ttlSeconds:timeout:)``.
/// Report the amount used with ``use(_:)``, then call ``finish()`` however the work ended, or
/// ``release()`` for work that never ran.
///
/// ```swift
/// let hold = try await customer.startHold(of: aiCredits, amount: 2_000, idempotencyKey: messageID)
/// try hold.use(0)
/// for try await chunk in stream { try hold.use(chunk.totalTokens) }
/// try await hold.finish()
/// ```
///
/// Only the first of ``finish()`` and ``release()`` acts; a later call answers the first one's
/// result. Each runs in a task of its own, so cancelling the caller cannot stop it halfway. A hold
/// never ended expires after its `ttlSeconds`, recording nothing;
/// ``Customer/withHold(of:amount:idempotencyKey:ttlSeconds:timeout:_:)`` always ends it.
public final class Hold: Sendable {
  /// The hold's id.
  public let id: String
  /// When the hold expires unless it is settled or released first.
  public let expiresAt: Date
  /// The answer that placed the hold, with the meter.
  public let result: UsageResult
  /// True when another caller holds the same key and may be doing the same work, so the app can
  /// wait for that caller's result instead of doing the work twice.
  public let isDuplicate: Bool
  let customer: any Customer
  let feature: String
  let key: String
  let timeout: TimeInterval?
  private let used = LockedValue<Int64?>(nil)
  private let ending = LockedValue<Task<UsageResult, any Error>?>(nil)

  init(
    id: String, expiresAt: Date, result: UsageResult, isDuplicate: Bool, customer: any Customer,
    feature: String, key: String, timeout: TimeInterval?
  ) {
    self.id = id
    self.expiresAt = expiresAt
    self.result = result
    self.isDuplicate = isDuplicate
    self.customer = customer
    self.feature = feature
    self.key = key
    self.timeout = timeout
  }

  /// The amount held.
  public var amount: Int64 { result.amount }

  /// Reports the total amount the work has used so far, with no request; a later call replaces an
  /// earlier one. Work that reports as it goes calls `use(0)` before it starts, so finishing after
  /// a failure that used nothing frees the whole hold.
  ///
  /// - Throws: ``ArgumentError`` for an amount below 0.
  public func use(_ amount: Int64) throws {
    guard amount >= 0 else { throw ArgumentError(message: Messages.amountUsed) }
    used.update { $0 = amount }
  }

  /// Ends the work, whether it succeeded, failed or was cut off, and charges for what happened:
  /// it settles the amount reported with ``use(_:)``, or the held amount when none was.
  ///
  /// Up to the held amount is settled, and any excess is recorded in observe mode under the hold's
  /// key plus `:excess`. When the hold expired first, the whole amount is recorded under that key,
  /// since the work happened.
  ///
  /// - Returns: The settlement, or the excess report when the hold had expired.
  /// - Throws: ``EntitlerError/usageSettlement(_:)`` when that fails after its retries.
  @discardableResult
  public func finish() async throws -> UsageResult {
    try await end { hold in try await hold.settle() }
  }

  /// Frees the hold, recording nothing, for work that never ran.
  @discardableResult
  public func release() async throws -> UsageResult {
    try await end { hold in try await hold.free() }
  }

  func dispose() async {
    guard ending.read() == nil else { return }
    let reported = used.read() != nil
    do {
      _ = try await end { hold in reported ? try await hold.settle() : try await hold.free() }
    } catch {
      customer.core.report(error)
    }
  }

  private func end(_ action: @escaping @Sendable (Hold) async throws -> UsageResult)
    async throws -> UsageResult
  {
    let task = ending.update { task in
      if let task { return task }
      let started = Task { try await action(self) }
      task = started
      return started
    }
    return try await task.value
  }

  private func free() async throws -> UsageResult {
    try await customer.releaseUsage(hold: id, timeout: timeout)
  }

  private func settle() async throws -> UsageResult {
    let total = used.read() ?? amount
    let settling = min(total, amount)
    let excess = total > amount ? total - amount : nil
    var unrecorded = excess
    var closed = false
    do {
      let settled: UsageResult
      do {
        settled = try await customer.settleUsage(hold: id, amount: settling, timeout: timeout)
        closed = true
      } catch EntitlerError.api(let error) where error.reason == .holdExpired {
        closed = true
        if total == 0 { return try await free() }
        unrecorded = total
        return try await recordExcess(total)
      }
      if let excess { _ = try await recordExcess(excess) }
      return settled
    } catch {
      throw EntitlerError.usageSettlement(
        UsageSettlementError(
          holdID: id, settled: closed, amount: settling, excess: unrecorded,
          excessKey: key + excessSuffix, underlyingError: error))
    }
  }

  private func recordExcess(_ amount: Int64) async throws -> UsageResult {
    try await customer.recordUsage(
      of: feature, amount: amount, idempotencyKey: key + excessSuffix, mode: .observe,
      timeout: timeout)
  }
}

let excessSuffix = ":excess"

extension Customer {
  /// Records usage of a metered feature. A refusal in gate mode is an answer, with
  /// ``UsageResult/outcome`` `refused`, not an error.
  ///
  /// ```swift
  /// let result = try await customer.recordUsage(of: exports, amount: 1, idempotencyKey: job.id)
  /// ```
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: How much was used, 1 or more.
  ///   - idempotencyKey: A key naming the event in your own system (this message, this export,
  ///     this webhook delivery), 1 to 200 printable ASCII characters. Entitler keeps it, so a retry
  ///     from another process or after a restart never counts twice.
  ///   - mode: ``UsageMode/gate`` (the default) or ``UsageMode/observe``.
  ///   - occurredAt: When the usage happened, so it counts in that period.
  ///   - register: Registers a customer not registered yet, if the key may register customers.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  @discardableResult
  public func recordUsage(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, mode: UsageMode? = nil,
    occurredAt: Date? = nil, register: Bool? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await recordUsage(
      of: feature.key, amount: amount, idempotencyKey: idempotencyKey, mode: mode,
      occurredAt: occurredAt, register: register, timeout: timeout)
  }

  /// Records usage of a metered feature named by its key.
  @discardableResult
  public func recordUsage(
    of feature: String, amount: Int64, idempotencyKey: String, mode: UsageMode? = nil,
    occurredAt: Date? = nil, register: Bool? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let key = try validIdempotencyKey(idempotencyKey)
    let body = UsageBody(
      featureKey: try require(feature, Messages.feature),
      amount: try positive(amount),
      idempotencyKey: key,
      mode: mode.map { "USAGE_MODE_" + $0.rawValue.uppercased() },
      occurredAtMs: try occurredAt.map(epochMilliseconds),
      register: register)
    return try await write(Wire.usageReportUsage, [:], body, key, timeout).answer
  }

  /// Holds an amount, answering a refusal instead of throwing; the building block of
  /// ``startHold(of:amount:idempotencyKey:ttlSeconds:timeout:)``.
  public func holdUsage(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await holdUsage(
      of: feature.key, amount: amount, idempotencyKey: idempotencyKey, ttlSeconds: ttlSeconds,
      timeout: timeout)
  }

  /// Holds an amount of a metered feature named by its key, answering a refusal instead of
  /// throwing.
  public func holdUsage(
    of feature: String, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await createHold(
      feature, amount, try validIdempotencyKey(idempotencyKey), ttlSeconds, timeout
    ).answer
  }

  /// Settles a hold with the amount really used, from 0 to the held amount.
  @discardableResult
  public func settleUsage(hold: String, amount: Int64, timeout: TimeInterval? = nil) async throws
    -> UsageResult
  {
    guard amount >= 0 else { throw ArgumentError(message: Messages.settledAmount) }
    return try await write(
      Wire.usageSettleHold, ["hold_id": try require(hold, Messages.hold)],
      SettleBody(amount: amount), nil, timeout
    ).answer
  }

  /// Frees a hold, recording nothing.
  @discardableResult
  public func releaseUsage(hold: String, timeout: TimeInterval? = nil) async throws
    -> UsageResult
  {
    try await write(
      Wire.usageReleaseHold, ["hold_id": try require(hold, Messages.hold)], nil as SettleBody?,
      nil, timeout
    ).answer
  }

  /// Holds an amount while work runs, and opens a ``Hold`` for it.
  ///
  /// - Parameters:
  ///   - ttlSeconds: How long the hold lasts, 1 to 3,600 seconds. Defaults to 300.
  /// - Throws: ``EntitlerError/usageRefused(_:)`` when the customer has too little left, and
  ///   ``EntitlerError/usageReplayed(_:)`` when the key's hold is already settled, released or
  ///   expired.
  public func startHold(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> Hold {
    try await startHold(
      of: feature.key, amount: amount, idempotencyKey: idempotencyKey, ttlSeconds: ttlSeconds,
      timeout: timeout)
  }

  /// Holds an amount of a metered feature named by its key, and opens a ``Hold`` for it.
  public func startHold(
    of feature: String, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> Hold {
    let key = try validIdempotencyKey(idempotencyKey, maxLength: 200 - excessSuffix.count)
    let (answer, retried) = try await createHold(feature, amount, key, ttlSeconds, timeout)
    if answer.outcome == .refused {
      throw EntitlerError.usageRefused(UsageRefusedError(result: answer))
    }
    let id = answer.holdID.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    }
    if answer.outcome == .held, id == nil || answer.expiresAt == nil {
      throw EntitlerError.api(
        APIError(
          status: 200, code: grpcCode(status: 500), reason: .responseInvalid, parameters: [:],
          requestID: nil, retryAfter: nil, idempotencyKey: key))
    }
    guard let id, let expiresAt = answer.expiresAt,
      answer.outcome == .held || (answer.outcome == .duplicate && expiresAt > answer.asOf)
    else { throw EntitlerError.usageReplayed(UsageReplayedError(result: answer)) }
    return Hold(
      id: id, expiresAt: expiresAt, result: answer,
      isDuplicate: answer.outcome == .duplicate && !retried, customer: self, feature: feature,
      key: key, timeout: timeout)
  }

  /// Holds an amount, runs `work`, then settles what `work` reported with ``Hold/use(_:)``, or the
  /// whole hold when it reported nothing. When `work` throws or is cancelled, settles what it
  /// reported, or frees the hold when it reported nothing, then rethrows.
  ///
  /// `work` receives the hold. When ``Hold/isDuplicate`` is true, another caller holds the same key
  /// and is doing the same work, so that caller settles the hold: `withHold` neither settles nor
  /// frees it, and `work` can return early to wait for the other caller's result.
  ///
  /// ```swift
  /// let summary = try await customer.withHold(
  ///   of: aiCredits, amount: 500, idempotencyKey: "summary-\(jobID)"
  /// ) { hold in
  ///   if hold.isDuplicate { return try await summaries.result(for: jobID) }
  ///   let answer = try await summarise(document)
  ///   try hold.use(answer.tokens)
  ///   return answer.summary
  /// }
  /// ```
  ///
  /// - Returns: What `work` returned.
  /// - Throws: ``EntitlerError/usageRefused(_:)`` before `work` runs when the customer has too
  ///   little left, `work`'s own error, and ``EntitlerError/usageSettlement(_:)`` carrying what
  ///   `work` returned when settling fails.
  public func withHold<Result: Sendable>(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil, _ work: (Hold) async throws -> Result
  ) async throws -> Result {
    try await withHold(
      of: feature.key, amount: amount, idempotencyKey: idempotencyKey, ttlSeconds: ttlSeconds,
      timeout: timeout, work)
  }

  /// Holds an amount of a metered feature named by its key, runs `work`, then settles it.
  public func withHold<Result: Sendable>(
    of feature: String, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil, _ work: (Hold) async throws -> Result
  ) async throws -> Result {
    let hold = try await startHold(
      of: feature, amount: amount, idempotencyKey: idempotencyKey, ttlSeconds: ttlSeconds,
      timeout: timeout)
    if hold.isDuplicate {
      try Task.checkCancellation()
      return try await work(hold)
    }
    let result: Result
    do {
      try Task.checkCancellation()
      result = try await work(hold)
    } catch {
      await hold.dispose()
      throw error
    }
    do {
      try await hold.finish()
    } catch EntitlerError.usageSettlement(var failure) {
      failure.result = result
      throw EntitlerError.usageSettlement(failure)
    }
    return result
  }

  private func createHold(
    _ feature: String, _ amount: Int64, _ key: String, _ ttlSeconds: Int?,
    _ timeout: TimeInterval?
  ) async throws -> (answer: UsageResult, retried: Bool) {
    if let ttlSeconds, !(1...3600).contains(ttlSeconds) {
      throw ArgumentError(message: Messages.ttlSeconds)
    }
    let body = UsageBody(
      featureKey: try require(feature, Messages.feature), amount: try positive(amount),
      idempotencyKey: key, ttlSeconds: ttlSeconds)
    return try await write(Wire.usageCreateHold, [:], body, key, timeout)
  }

  private func write<Body: Encodable>(
    _ route: Route, _ variables: [String: String], _ body: Body?, _ key: String?,
    _ timeout: TimeInterval?
  ) async throws -> (answer: UsageResult, retried: Bool) {
    var request = try route.request(variables.merging(["external_id": id]) { $1 })
    request.body = try body.map { try JSONEncoder().encode($0) }
    request.idempotencyKey = key
    request.retryable = true
    request.timeout = timeout
    return try await core.call(request, decode: decodeUsage)
  }
}

private struct UsageBody: Encodable {
  var featureKey: String
  var amount: Int64
  var idempotencyKey: String
  var mode: String? = nil
  var occurredAtMs: Int64? = nil
  var register: Bool? = nil
  var ttlSeconds: Int? = nil
}

private struct SettleBody: Encodable {
  var amount: Int64
}

private func positive(_ amount: Int64) throws -> Int64 {
  guard amount > 0 else { throw ArgumentError(message: Messages.usageAmount) }
  return amount
}

private func epochMilliseconds(_ date: Date) throws -> Int64 {
  let milliseconds = (date.timeIntervalSince1970 * 1000).rounded(.down)
  guard milliseconds >= 0, let value = Int64(exactly: milliseconds) else {
    throw ArgumentError(message: Messages.occurredAt)
  }
  return value
}

private func validIdempotencyKey(_ key: String, maxLength: Int = 200) throws -> String {
  let bytes = Array(key.utf8)
  guard !bytes.isEmpty, bytes.count <= maxLength,
    bytes.allSatisfy({ (0x20...0x7E).contains($0) }), bytes.first != 0x20, bytes.last != 0x20
  else {
    throw ArgumentError(
      message: "Pass idempotencyKey as 1 to \(maxLength) printable ASCII characters.")
  }
  return key
}
