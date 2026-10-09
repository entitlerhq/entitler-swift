import Foundation

/// The pattern a visitor id matches: 16 to 64 letters, numbers, hyphens or underscores.
public let visitorIDPattern = "^[A-Za-z0-9_-]{16,64}$"

/// A new visitor id: 24 random bytes, base64url without padding (32 characters).
///
/// A server keeps one per visitor, for example in a first-party cookie, so the same person sees
/// the same experiment arm on every page and after signing up.
public func newVisitorID() -> String {
  var generator = SystemRandomNumberGenerator()
  return Base64URL.encode(
    Data((0..<24).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

func validVisitor(_ visitor: String?) throws -> String? {
  guard let visitor else { return nil }
  guard visitor.range(of: visitorIDPattern, options: .regularExpression) != nil else {
    throw ArgumentError(message: Messages.visitor)
  }
  return visitor
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

func storedVisitor() -> String {
  #if canImport(Darwin)
    let key = "entitler.visitor"
    if let kept = UserDefaults.standard.string(forKey: key), (try? validVisitor(kept)) != nil {
      return kept
    }
    let visitor = newVisitorID()
    UserDefaults.standard.set(visitor, forKey: key)
    return visitor
  #else
    return newVisitorID()
  #endif
}
