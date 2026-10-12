import Foundation

/// The pattern a visitor id matches: 16 to 64 letters, numbers, hyphens or underscores.
public let visitorIDPattern = #"\A[A-Za-z0-9_-]{16,64}\z"#

/// A new visitor id: 24 random bytes, base64url without padding (32 characters).
///
/// A server keeps one per visitor, for example in a first-party cookie, so the same person sees
/// the same experiment arm on every page and after signing up.
public func newVisitorID() -> String { randomVisitorID() }

func randomVisitorID() -> String {
  var generator = SystemRandomNumberGenerator()
  return Base64URL.encode(
    Data((0..<24).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

func validVisitor(_ visitor: String?) throws -> String? {
  guard let visitor else { return nil }
  guard (16...64).contains(visitor.utf8.count), visitor.utf8.allSatisfy(isVisitorByte) else {
    throw ArgumentError(message: Messages.visitor)
  }
  return visitor
}

private func isVisitorByte(_ byte: UInt8) -> Bool {
  switch byte {
  case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
    UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
    true
  default: false
  }
}

func validIdempotencyKey(
  _ key: String?, maxLength: Int = 200, message: String = Messages.idempotencyKey
) throws -> String? {
  guard let key else { return nil }
  guard (1...maxLength).contains(key.utf8.count),
    key.utf8.allSatisfy({ (0x20...0x7e).contains($0) }), key.first != " ", key.last != " "
  else { throw ArgumentError(message: message) }
  return key
}

#if canImport(Darwin)
  /// The visitor id the in-app client keeps in `UserDefaults.standard`, creating and keeping one
  /// when none is kept. Needs no client: a signed-out screen sends it with the app's sign-up
  /// request, so the server's `register(visitor:)` keeps the person's experiment arm.
  public func storedVisitorID() -> String {
    storedVisitorLock.lock()
    defer { storedVisitorLock.unlock() }
    if let kept = UserDefaults.standard.string(forKey: storedVisitorKey),
      (try? validVisitor(kept)) != nil
    {
      return kept
    }
    let visitor = randomVisitorID()
    UserDefaults.standard.set(visitor, forKey: storedVisitorKey)
    return visitor
  }

  /// Forgets the kept visitor id, so the next read creates a new one. Call it at sign-out and at
  /// account deletion, so the next person on a shared device is never linked to the last.
  public func resetStoredVisitor() {
    storedVisitorLock.lock()
    defer { storedVisitorLock.unlock() }
    UserDefaults.standard.removeObject(forKey: storedVisitorKey)
  }

  private let storedVisitorKey = "entitler.visitor"
  private let storedVisitorLock = NSLock()

  func storedVisitor() -> String { storedVisitorID() }
#else
  func storedVisitor() -> String { newVisitorID() }
#endif
