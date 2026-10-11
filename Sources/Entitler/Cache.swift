import Foundation

/// A store for kept answers, after `NSCache`: implement it to share answers through Redis or keep
/// them on disk across launches. It must be safe for concurrent use.
///
/// A thrown ``entry(forKey:)`` counts as a miss and a thrown ``setEntry(_:forKey:timeToLive:)`` is
/// skipped; each goes to ``EntitlerOptions/onError`` and neither fails the call.
public protocol CacheStore: Sendable {
  /// The entry kept under a key, or `nil`.
  func entry(forKey key: String) async throws -> CacheEntry?

  /// Keeps an entry under a key, replacing any before it.
  ///
  /// - Parameters:
  ///   - entry: The entry to keep.
  ///   - key: A lowercase hex SHA-256, never holding a credential.
  ///   - timeToLive: How long the entry is useful, in seconds: the client's `staleFor` plus the
  ///     answer's `max-age`. Stores that expire entries should expire it after that.
  func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws
}

/// A kept answer: plain values, so a store can keep it as JSON.
///
/// Entries are private to this SDK: sharing a store with SDKs in other languages is not
/// supported.
public struct CacheEntry: Codable, Hashable, Sendable {
  /// The entry format, 1.
  public var v: Int
  /// The answer's body, as raw JSON text.
  public var body: String
  /// The answer's `ETag`.
  public var etag: String?
  /// The answer's `Cache-Control` header.
  public var cacheControl: String?
  /// The answer's `Age` header, in seconds.
  public var age: Int?
  /// When the answer was received.
  public var receivedAt: Date

  /// Creates an entry.
  public init(body: String, etag: String?, cacheControl: String?, age: Int?, receivedAt: Date) {
    v = 1
    self.body = body
    self.etag = etag
    self.cacheControl = cacheControl
    self.age = age
    self.receivedAt = receivedAt
  }

  var directives: [String] {
    (cacheControl ?? "").lowercased().split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
  }

  var maxAge: TimeInterval? {
    directives.first { $0.hasPrefix("max-age=") }.flatMap { TimeInterval($0.dropFirst(8)) }
  }

  func isFresh(at now: Date) -> Bool {
    guard let maxAge, !directives.contains("no-cache") else { return false }
    return now.timeIntervalSince(receivedAt) + TimeInterval(age ?? 0) < maxAge
  }
}

/// The default store: answers in memory, least recently used out first.
public actor MemoryCacheStore: CacheStore {
  private let capacity: Int
  private var entries: [String: (entry: CacheEntry, used: UInt64)] = [:]
  private var clock: UInt64 = 0
  private var asked: (@Sendable (String) -> Void)?

  /// Creates a store that keeps at most `capacity` answers.
  public init(capacity: Int) {
    self.capacity = max(1, capacity)
  }

  /// The entry kept under a key, marked as just used.
  public func entry(forKey key: String) -> CacheEntry? {
    asked?(key)
    guard let kept = entries[key] else { return nil }
    clock += 1
    entries[key] = (kept.entry, clock)
    return kept.entry
  }

  /// Keeps an entry, dropping the least recently used one when full. Entries never expire here.
  public func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) {
    clock += 1
    entries[key] = (entry, clock)
    if entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
      entries[oldest.key] = nil
    }
  }

  func removeAll() { entries = [:] }

  func observe(_ hook: @escaping @Sendable (String) -> Void) { asked = hook }
}
