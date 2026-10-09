import Foundation

/// A store for kept answers, after `NSCache`: implement it to share answers through Redis or keep
/// them on disk across launches. It must be safe for concurrent use.
public protocol CacheStore: Sendable {
  /// The entry kept under a key, or `nil`.
  func entry(forKey key: String) async -> CacheEntry?
  /// Keeps an entry under a key, replacing any before it.
  func setEntry(_ entry: CacheEntry, forKey key: String) async
}

/// A kept answer. Keys are SHA-256 hashes and never contain a credential.
public struct CacheEntry: Codable, Hashable, Sendable {
  /// The answer's body.
  public var body: Data
  /// The answer's `ETag`.
  public var etag: String?
  /// How long the answer is fresh, in seconds, from `Cache-Control: max-age`.
  public var maxAge: TimeInterval?
  /// When the answer was received.
  public var receivedAt: Date

  /// Creates an entry.
  public init(body: Data, etag: String?, maxAge: TimeInterval?, receivedAt: Date) {
    self.body = body
    self.etag = etag
    self.maxAge = maxAge
    self.receivedAt = receivedAt
  }
}

/// The default store: answers in memory, least recently used out first.
public actor MemoryCacheStore: CacheStore {
  private let capacity: Int
  private var entries: [String: (entry: CacheEntry, used: UInt64)] = [:]
  private var clock: UInt64 = 0

  /// Creates a store that keeps at most `capacity` answers.
  public init(capacity: Int) {
    self.capacity = max(1, capacity)
  }

  /// The entry kept under a key, marked as just used.
  public func entry(forKey key: String) -> CacheEntry? {
    guard let kept = entries[key] else { return nil }
    clock += 1
    entries[key] = (kept.entry, clock)
    return kept.entry
  }

  /// Keeps an entry, dropping the least recently used one when full.
  public func setEntry(_ entry: CacheEntry, forKey key: String) {
    clock += 1
    entries[key] = (entry, clock)
    if entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
      entries[oldest.key] = nil
    }
  }
}
