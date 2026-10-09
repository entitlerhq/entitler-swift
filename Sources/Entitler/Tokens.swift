import Foundation

/// Supplies a fresh token: a customer token from your server, or an identity token from your
/// sign-in provider. The client asks again before the kept token expires and after a `401`.
public typealias TokenProvider = @Sendable () async throws -> String

enum JWT {
  static func claims(_ token: String) -> [String: Any]? {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3, let payload = Base64URL.decode(segments[1]) else { return nil }
    return (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
  }

  static func principal(_ token: String, claims names: [String]) -> String {
    guard let claims = claims(token) else { return token }
    return names.map { "\(claims[$0] ?? "")" }.joined(separator: "\n")
  }
}

actor TokenSource {
  private let provider: TokenProvider?
  private let blankMessage: String
  private var current: String?
  private var expiresAt: Date?
  private var refreshing: Task<String, any Error>?

  init(fixed token: String) {
    provider = nil
    blankMessage = ""
    current = token
  }

  init(provider: @escaping TokenProvider, blankMessage: String) {
    self.provider = provider
    self.blankMessage = blankMessage
  }

  var canRefresh: Bool { provider != nil }

  func token(now: Date) async throws -> String {
    if let current, provider == nil || expiresAt.map({ $0.timeIntervalSince(now) > 60 }) ?? true {
      return current
    }
    return try await refresh()
  }

  func refresh(replacing rejected: String) async throws -> String? {
    guard provider != nil else { return nil }
    if let current, current != rejected, refreshing == nil { return current }
    return try await refresh()
  }

  private func refresh() async throws -> String {
    if let refreshing { return try await refreshing.value }
    guard let provider else {
      throw EntitlerError.token(TokenError(message: blankMessage, underlyingError: nil))
    }
    let blankMessage = blankMessage
    let task = Task<String, any Error> {
      let answer: String
      do {
        answer = try await provider()
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw EntitlerError.token(
          TokenError(
            message: "The token provider failed: \(error.localizedDescription)",
            underlyingError: error))
      }
      let token = answer.trimmed
      guard !token.isEmpty else {
        throw EntitlerError.token(TokenError(message: blankMessage, underlyingError: nil))
      }
      guard JWT.claims(token) != nil else {
        throw EntitlerError.token(
          TokenError(
            message: "The token provider answered a token that is not a JWT.", underlyingError: nil)
        )
      }
      return token
    }
    refreshing = task
    defer { refreshing = nil }
    let token = try await task.value
    current = token
    expiresAt = (JWT.claims(token)?["exp"] as? NSNumber).map {
      Date(timeIntervalSince1970: $0.doubleValue)
    }
    return token
  }
}
