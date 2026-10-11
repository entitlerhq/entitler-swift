import Foundation

/// Supplies a fresh token: a customer token from your server, or an identity token from your
/// sign-in provider.
///
/// The client asks again before the kept token expires and after a `401`. An error it throws is
/// kept as the ``TokenError/underlyingError``, as it is: its contents are outside the SDK's control.
public typealias TokenProvider = @Sendable () async throws -> String

enum JWT {
  static func lifetime(_ token: String) -> (iat: Int64?, exp: Int64)? {
    struct Lifetime: Decodable {
      let iat: Int64?
      let exp: Int64
    }
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3, let payload = Base64URL.decode(segments[1]),
      let lifetime = try? JSONDecoder().decode(Lifetime.self, from: payload),
      lifetime.iat.map({ $0 < lifetime.exp }) ?? true
    else { return nil }
    return (lifetime.iat, lifetime.exp)
  }
}

actor TokenSource: CustomStringConvertible, CustomReflectable {
  private let provider: TokenProvider?
  private let blankMessage: String
  private(set) var current: String?
  private var refreshAt: Date?
  private var refreshing: Task<String, any Error>?

  nonisolated var description: String { "TokenSource" }
  nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }

  init(fixed token: String) {
    provider = nil
    blankMessage = ""
    current = token
  }

  init(provider: @escaping TokenProvider, blankMessage: String) {
    self.provider = provider
    self.blankMessage = blankMessage
  }

  func token(now: Date, timeout: TimeInterval) async throws -> String {
    if let current, provider == nil || refreshAt.map({ now < $0 }) ?? true { return current }
    return try await refresh(now: now, timeout: timeout)
  }

  func refresh(replacing rejected: String, now: Date, timeout: TimeInterval) async throws -> String?
  {
    guard provider != nil else { return nil }
    if let current, current != rejected { return current }
    return try await refresh(now: now, timeout: timeout)
  }

  private func refresh(now: Date, timeout: TimeInterval) async throws -> String {
    let task = refreshing ?? started(timeout: timeout)
    do {
      let token = try await waitCancellably(for: task)
      settle(task, outcome: .success(token))
      return token
    } catch {
      if !Task.isCancelled { settle(task, outcome: .failure(error)) }
      throw error
    }
  }

  private func started(timeout: TimeInterval) -> Task<String, any Error> {
    let task = start(timeout: timeout)
    refreshing = task
    Task {
      let outcome = await task.result
      settle(task, outcome: outcome)
    }
    return task
  }

  private func settle(_ task: Task<String, any Error>, outcome: Result<String, any Error>) {
    guard refreshing == task else { return }
    refreshing = nil
    guard case .success(let token) = outcome else { return }
    current = token
    refreshAt = Self.refreshTime(of: token, receivedAt: Hooks.current.now())
  }

  private func start(timeout: TimeInterval) -> Task<String, any Error> {
    let provider = provider
    let blankMessage = blankMessage
    let hooks = Hooks.current
    return Task {
      guard let provider else {
        throw EntitlerError.token(TokenError(message: blankMessage, underlyingError: nil))
      }
      let answer: String?
      do {
        answer = try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask { try await provider() }
          group.addTask {
            try await hooks.deadline(timeout)
            return nil
          }
          defer { group.cancelAll() }
          return try await group.next() ?? nil
        }
      } catch {
        throw EntitlerError.token(
          TokenError(
            message: "The token provider failed: \(error.localizedDescription)",
            underlyingError: error))
      }
      guard let answer else {
        throw EntitlerError.token(
          TokenError(
            message: "The token provider did not answer within \(timeout.formatted()) seconds.",
            underlyingError: nil))
      }
      let token = answer.trimmed
      guard !token.isEmpty else {
        throw EntitlerError.token(TokenError(message: blankMessage, underlyingError: nil))
      }
      guard token.isHeaderSafe, JWT.lifetime(token) != nil else {
        throw EntitlerError.token(
          TokenError(
            message:
              "The token provider answered a token that is not a readable JWT with an expiry.",
            underlyingError: nil)
        )
      }
      return token
    }
  }

  func cancel() {
    refreshing?.cancel()
    refreshing = nil
  }

  static func refreshTime(of token: String, receivedAt: Date) -> Date? {
    guard let lifetime = JWT.lifetime(token) else { return nil }
    let exp = TimeInterval(lifetime.exp)
    let start = lifetime.iat.map(TimeInterval.init) ?? receivedAt.timeIntervalSince1970
    let margin = min(60, max(0, exp - start) / 2)
    return Date(timeIntervalSince1970: exp - margin)
  }
}

func waitCancellably<Value: Sendable>(for task: Task<Value, any Error>) async throws -> Value {
  let state = LockedValue<CheckedContinuation<Value, any Error>?>(nil)
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      state.set(continuation)
      Task {
        let result = await task.result
        state.take()?.resume(with: result)
      }
      if Task.isCancelled { state.take()?.resume(throwing: CancellationError()) }
    }
  } onCancel: {
    state.take()?.resume(throwing: CancellationError())
  }
}

final class LockedValue<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func set(_ value: Value) {
    lock.lock()
    defer { lock.unlock() }
    self.value = value
  }

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

extension LockedValue {
  func take<Wrapped>() -> Wrapped? where Value == Wrapped? {
    lock.lock()
    defer { lock.unlock() }
    let taken = value
    value = nil
    return taken
  }
}
