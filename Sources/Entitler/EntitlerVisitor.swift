import Foundation

/// The visitor client, built from a publishable key, for an app or page with no signed-in
/// customer, such as a pricing screen.
///
/// ```swift
/// let entitler = try EntitlerVisitor(key: publishableKey)
/// let sheet = try await entitler.pricing(country: "AU", locale: .current)
/// ```
///
/// Answers are kept in memory only.
public final class EntitlerVisitor: Sendable, CustomStringConvertible, CustomReflectable {
  let core: Core

  /// Creates a visitor client.
  ///
  /// - Parameters:
  ///   - key: A publishable key from the dashboard. It is safe to ship in an app.
  ///   - cache: A ``MemoryCacheStore`` of another size, or `nil` for none.
  ///   - options: The base URL, timeouts, retries and how long a kept answer may stand in.
  /// - Throws: ``ArgumentError`` for a blank key.
  public convenience init(
    key: String, cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    try self.init(
      key: requireCredential(key, Messages.publishableKey), cache: cache, options: options,
      exchange: nil, hooks: Hooks())
  }

  init(
    key: String, cache: MemoryCacheStore?, options: EntitlerOptions, exchange: Exchange?,
    hooks: Hooks
  ) throws {
    core = try Core(
      options: options, cache: cache, credentials: .key(key), exchange: exchange, hooks: hooks)
  }

  /// Reads the plans on sale on the default track, priced in `market`, or in `country`'s market.
  /// With neither, the plans come with no prices.
  ///
  /// - Parameters:
  ///   - market: The key of the market to price the plans in.
  ///   - country: The ISO 3166-1 country code whose market prices the plans, when `market` is
  ///     left out.
  ///   - locale: The locale to format amounts' `display` for, sent as `Accept-Language`.
  ///   - revalidate: Asks Entitler whether a kept answer still stands before using it.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  public func pricing(
    market: String? = nil, country: String? = nil, locale: Locale? = nil,
    revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> PricingSheet {
    try await Entitler.pricing(
      core, market: market, country: country, locale: locale, revalidate: revalidate,
      timeout: timeout)
  }

  /// Reads the catalogue's features on the default track, archived ones included, as the served
  /// version describes them.
  public func features(revalidate: Bool = false, timeout: TimeInterval? = nil) async throws
    -> FeatureList
  {
    try await Entitler.features(core, revalidate: revalidate, timeout: timeout)
  }

  /// The public keys that verify snapshots. Sent with no credential.
  public func snapshotKeys(timeout: TimeInterval? = nil) async throws -> SnapshotKeySet {
    try await Entitler.snapshotKeys(core, timeout: timeout)
  }

  /// Closes the client: cancels every call in flight, drops the in-memory cache, and makes every
  /// later call throw ``ClientClosedError``. Closing twice is safe.
  public func close() { core.close() }

  /// Shows the base URL, never the key.
  public var description: String { "EntitlerVisitor(\(core.options.base))" }

  /// Shows the base URL, never the key.
  public var customMirror: Mirror { core.customMirror }
}
