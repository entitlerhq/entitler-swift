import Foundation

protocol StaleMarking {
  var stale: Bool { get set }
}

func markedStale<Value>(_ value: Value) -> Value {
  guard var marked = value as? any StaleMarking else { return value }
  marked.stale = true
  return (marked as? Value) ?? value
}

final class LockedValue<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func read() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func swap(_ replacement: Value) -> Value {
    lock.lock()
    defer { lock.unlock() }
    let old = value
    value = replacement
    return old
  }

  @discardableResult
  func update<Result>(_ change: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return change(&value)
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n")) }

  var componentEncoded: String {
    var allowed = CharacterSet(charactersIn: "-_.!~*'()")
    allowed.formUnion(CharacterSet(charactersIn: "a"..."z"))
    allowed.formUnion(CharacterSet(charactersIn: "A"..."Z"))
    allowed.formUnion(CharacterSet(charactersIn: "0"..."9"))
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }

  var isHeaderSafe: Bool { utf8.allSatisfy { (0x21...0x7E).contains($0) } }
}

func require(_ value: String, _ message: String) throws -> String {
  guard !value.trimmed.isEmpty else { throw ArgumentError(message: message) }
  return value
}

func requireCredential(_ value: String, _ message: String) throws -> String {
  let credential = value.trimmed
  guard !credential.isEmpty, credential.isHeaderSafe else {
    throw ArgumentError(message: message)
  }
  return credential
}

func headerNumber<Text: StringProtocol>(_ text: Text) -> Int? {
  let digits = text.trimmingCharacters(in: .whitespaces)
  guard !digits.isEmpty, digits.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
  return Int(digits) ?? .max
}

enum Messages {
  static let key = "Provide an Entitler key from the dashboard."
  static let customerID = "Provide the id your app uses for the customer."
  static let feature = "Name the feature by its key."
  static let asOf = "Pass asOf as a valid date."
  static let dots = "Pass an id that is not made only of dots."
  static let timeout = "Pass timeout as a number of seconds above 0."
  static let hold = "Provide the id of the hold."
  static let usageAmount = "Pass amount as a whole number of 1 or more."
  static let settledAmount = "Pass amount as a whole number from 0 to the held amount."
  static let amountUsed = "Pass the amount used as a whole number of 0 or more."
  static let ttlSeconds = "Pass ttlSeconds as a whole number from 1 to 3600."
  static let occurredAt = "Pass occurredAt as a valid date."
}
