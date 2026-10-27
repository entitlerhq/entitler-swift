import Foundation

/// A customer: the checks and usage both clients share.
public protocol Customer: Sendable {
  /// The id your app uses for the customer.
  var id: String { get }
  /// The client this customer acts through. Opaque.
  var handle: CustomerHandle { get }
}

/// The client a ``Customer`` acts through. Opaque.
public struct CustomerHandle: Sendable {
  let core: Core
}

extension Customer {
  var core: Core { handle.core }

  /// Checks one feature: Entitler's decision, the value, where it comes from and the plans that
  /// would give it. A metered feature's check carries its meter.
  ///
  /// ```swift
  /// let check = try await customer.check(Feature<Metered>("ai_credits"))
  /// if !check.entitled { showUpgrade(check.upgrades) }
  /// ```
  ///
  /// - Parameters:
  ///   - feature: The feature, declared with its kind.
  ///   - asOf: Answers as of this instant instead of now, in a test environment whose plan allows
  ///     the test clock. A live environment refuses it with ``Reason/asOfNotAllowed``.
  ///   - revalidate: Asks Entitler even when a kept answer is still fresh.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  /// - Throws: ``ArgumentError`` when Entitler answers the feature as another type than declared.
  public func check<Kind>(
    _ feature: Feature<Kind>, asOf: Date? = nil, revalidate: Bool = false,
    timeout: TimeInterval? = nil
  ) async throws -> Kind.Check {
    let check = try await self.check(
      feature.key, asOf: asOf, revalidate: revalidate, timeout: timeout)
    guard check.type == Kind.type else {
      throw ArgumentError(
        message:
          "\(feature.key) is declared \(Kind.type), but Entitler answers it as \(check.type).")
    }
    if let answer = check as? Kind.Check { return answer }
    guard let meter = check.meter,
      let answer = MeteredCheck(
        entitlement: check.entitlement, meter: meter, context: check.context, stale: check.stale)
        as? Kind.Check
    else {
      throw EntitlerError.api(
        APIError(
          status: 200, code: grpcCode(status: 500), reason: .responseInvalid, parameters: [:],
          requestID: nil, retryAfter: nil, idempotencyKey: nil))
    }
    return answer
  }

  /// Checks one feature by its key.
  public func check(
    _ feature: String, asOf: Date? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Check {
    try await read(feature, asOf, revalidate, timeout, decodeCheck)
  }

  /// Answers Entitler's decision for one feature, or `fallback` when Entitler cannot be asked.
  /// Never throws: a failed request goes to ``EntitlerOptions/onError``.
  ///
  /// - Parameters:
  ///   - feature: The feature's key.
  ///   - fallback: The answer when Entitler cannot be asked. Pass `false` for paid features, and
  ///     `true` only where losing a sale is worse than giving the feature away.
  public func isEntitled(
    to feature: String, default fallback: Bool, asOf: Date? = nil, revalidate: Bool = false,
    timeout: TimeInterval? = nil
  ) async -> Bool {
    do {
      return try await check(feature, asOf: asOf, revalidate: revalidate, timeout: timeout)
        .entitled
    } catch is CancellationError {
      return fallback
    } catch {
      if !Task.isCancelled { core.report(error) }
      return fallback
    }
  }

  /// Answers Entitler's decision for a declared feature, or `fallback` when Entitler cannot be
  /// asked.
  public func isEntitled<Kind>(
    to feature: Feature<Kind>, default fallback: Bool, asOf: Date? = nil,
    revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async -> Bool {
    await isEntitled(
      to: feature.key, default: fallback, asOf: asOf, revalidate: revalidate, timeout: timeout)
  }

  /// Lists every entitlement the customer holds, groups included.
  ///
  /// ```swift
  /// let entitlements = try await customer.entitlements()
  /// if entitlements.has("collaboration") { showSharing() }
  /// ```
  public func entitlements(
    asOf: Date? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Entitlements {
    var request = try Wire.entitlementsListEntitlements.request(
      ["external_id": id], query: try asOfQuery(asOf))
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request, decode: decodeEntitlements)
  }

  private func read<Answer: Sendable>(
    _ feature: String, _ asOf: Date?, _ revalidate: Bool, _ timeout: TimeInterval?,
    _ decode: @escaping @Sendable (Data) throws -> Answer
  ) async throws -> Answer {
    var request = try Wire.entitlementsCheckFeature.request(
      ["external_id": id, "feature_key": require(feature, Messages.feature)],
      query: try asOfQuery(asOf))
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request, decode: decode)
  }
}

private func asOfQuery(_ asOf: Date?) throws -> [(name: String, value: String)] {
  guard let asOf else { return [] }
  guard asOf.timeIntervalSince1970 >= 0,
    let seconds = Int64(exactly: asOf.timeIntervalSince1970.rounded(.down))
  else {
    throw ArgumentError(message: Messages.asOf)
  }
  return [("as_of", String(seconds))]
}
