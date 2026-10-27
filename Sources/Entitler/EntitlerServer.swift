import Foundation

/// The server client, built from a secret key. It runs on your servers and acts on any customer.
///
/// ```swift
/// let entitler = try EntitlerServer(key: key)
/// let ada = try entitler.customer("ada")
/// if await ada.isEntitled(to: "priority_support", default: false) {
///   openTicket()
/// }
/// ```
public final class EntitlerServer: Sendable, CustomStringConvertible, CustomReflectable {
  let core: Core

  /// Creates a server client.
  ///
  /// - Parameters:
  ///   - key: A secret key from the dashboard. Keep it on your servers; never ship it in an app.
  ///   - cache: Where to keep answers: a ``MemoryCacheStore`` of another size, any
  ///     ``CacheStore`` to share answers between processes, or `nil` for none.
  ///   - options: The base URL, timeouts, retries and how long a kept answer may stand in.
  /// - Throws: ``ArgumentError`` for a blank key.
  public init(
    key: String, cache: (any CacheStore)? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    core = try Core(
      options: options, cache: cache, credentials: .key(requireCredential(key, Messages.key)))
  }

  init(
    key: String, cache: (any CacheStore)?, options: EntitlerOptions,
    exchange: @escaping Exchange, hooks: Hooks
  ) throws {
    core = try Core(
      options: options, cache: cache, credentials: .key(key), exchange: exchange, hooks: hooks)
  }

  /// The customer with the id your app uses for them. Makes no request.
  ///
  /// - Throws: ``ArgumentError`` for a blank id, or for `me`, which names an app's signed-in
  ///   customer.
  public func customer(_ id: String) throws -> ServerCustomer {
    let given = try require(id, Messages.customerID)
    guard given != "me" else { throw ArgumentError(message: Messages.me) }
    return ServerCustomer(id: given, handle: CustomerHandle(core: core))
  }

  /// Closes the client: cancels every call in flight, drops the in-memory cache (a custom store is
  /// left as it is), and makes every later call throw ``ClientClosedError``. Closing twice is safe.
  public func close() { core.close() }

  /// Shows the base URL, never the key.
  public var description: String { "EntitlerServer(\(core.options.base))" }

  /// Shows the base URL, never the key.
  public var customMirror: Mirror { core.customMirror }
}
