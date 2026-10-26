import Foundation

/// A failure the SDK raises.
///
/// Catch one kind with a pattern:
///
/// ```swift
/// do {
///   let check = try await customer.check("priority_support")
/// } catch EntitlerError.api(let error) where error.reason == .customerNotFound {
///   showSignUp()
/// }
/// ```
///
/// Cancelling the task surfaces `CancellationError`, an invalid argument ``ArgumentError``, and a
/// closed client ``ClientClosedError``; none is an `EntitlerError`. No error holds a credential,
/// a request or a request's headers.
public enum EntitlerError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The API answered with a status other than 2xx, or with a 2xx answer this SDK cannot read.
  case api(APIError)
  /// No answer arrived: DNS, TLS, or a refused, reset or cut-off connection.
  case connection(ConnectionError)
  /// An attempt took longer than its timeout.
  case timeout(TimeoutError)

  /// The message of the error this case carries.
  public var errorDescription: String? { description }

  /// The message of the error this case carries.
  public var description: String {
    switch self {
    case .api(let error): error.description
    case .connection(let error): error.message
    case .timeout(let error): error.message
    }
  }

  /// True when Entitler could not be reached: no answer, a timeout, a `429`, a `5xx` or an answer
  /// this SDK cannot read. An app that can work offline falls back to its last known answer.
  public var isUnreachable: Bool {
    switch self {
    case .connection, .timeout: true
    case .api(let error):
      error.status == 429 || error.status >= 500 || error.reason == .responseInvalid
    }
  }

  var apiError: APIError? {
    if case .api(let error) = self { return error }
    return nil
  }
}

/// The API answered with a status other than 2xx, or with a 2xx answer this SDK cannot read.
public struct APIError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The HTTP status.
  public let status: Int
  /// The gRPC status name, such as `NotFound` or `PermissionDenied`.
  public let code: String
  /// Why the API refused, such as ``Reason/customerNotFound``, or `nil` when the answer had no
  /// readable error body.
  public let reason: Reason?
  /// The reason's parameters, such as `field` for an invalid argument.
  public let parameters: [String: String]
  /// The `x-request-id` header, for Entitler support.
  public let requestID: String?
  /// How long the API asked to wait before trying again, in seconds.
  public let retryAfter: TimeInterval?
  /// The idempotency key the request sent, so the call can be repeated later with it.
  public let idempotencyKey: String?
  /// What went wrong underneath, such as the decoding failure behind
  /// ``Reason/responseInvalid``.
  public internal(set) var underlyingError: (any Error)? = nil

  /// The message.
  public var errorDescription: String? { description }

  /// Names the reason, or the code when there is none, and the HTTP status.
  public var description: String {
    "Entitler answered \(reason?.rawValue ?? code) (HTTP \(status))."
  }
}

/// Why the API refused a request, extensible like `Notification.Name`: a reason this SDK does not
/// list is kept as it is.
public struct Reason: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The reason as the API spells it, such as `CUSTOMER_NOT_FOUND`.
  public let rawValue: String

  /// Creates a reason from the API's spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The reason as the API spells it.
  public var description: String { rawValue }

  /// No customer has the id.
  public static let customerNotFound = Reason(rawValue: "CUSTOMER_NOT_FOUND")
  /// The catalogue has no feature with the key.
  public static let featureNotFound = Reason(rawValue: "FEATURE_NOT_FOUND")
  /// The customer named in the path is not one the credential may name.
  public static let customerRefInvalid = Reason(rawValue: "CUSTOMER_REF_INVALID")
  /// The request carried no credential.
  public static let credentialRequired = Reason(rawValue: "CREDENTIAL_REQUIRED")
  /// The key is unknown, revoked or expired.
  public static let keyInactive = Reason(rawValue: "KEY_INACTIVE")
  /// The credential may not make this call.
  public static let permissionDenied = Reason(rawValue: "PERMISSION_DENIED")
  /// Too many requests for this credential; wait for ``APIError/retryAfter``.
  public static let apiRateLimited = Reason(rawValue: "API_RATE_LIMITED")
  /// The environment used its plan's request allowance; wait for ``APIError/retryAfter``.
  public static let apiAllowanceReached = Reason(rawValue: "API_ALLOWANCE_REACHED")
  /// `asOf` was passed in an environment that does not allow the test clock.
  public static let asOfNotAllowed = Reason(rawValue: "AS_OF_NOT_ALLOWED")
  /// The SDK's own: a 2xx answer it cannot read.
  public static let responseInvalid = Reason(rawValue: "RESPONSE_INVALID")
}

/// No answer arrived from Entitler.
public struct ConnectionError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The `URLError` behind it.
  public let underlyingError: any Error
  /// The idempotency key the request sent, when it sent one.
  public let idempotencyKey: String?

  /// The message.
  public var message: String {
    "Entitler could not be reached: \(underlyingError.localizedDescription)"
  }

  /// The message.
  public var errorDescription: String? { message }

  /// The message.
  public var description: String { message }
}

/// An attempt took longer than its timeout.
public struct TimeoutError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The timeout, in seconds.
  public let timeout: TimeInterval
  /// The idempotency key the request sent, when it sent one.
  public let idempotencyKey: String?

  /// The message.
  public var message: String { "Entitler did not answer within \(timeout.formatted()) seconds." }

  /// The message.
  public var errorDescription: String? { message }

  /// The message.
  public var description: String { message }
}

/// An argument the SDK cannot use, raised before any request.
public struct ArgumentError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible {
  /// What to pass instead.
  public let message: String

  /// The message.
  public var errorDescription: String? { message }

  /// The message.
  public var description: String { message }
}

/// A call on a client after ``EntitlerServer/close()``.
public struct ClientClosedError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible
{
  /// The message.
  public let message = "This Entitler client is closed. Create a new one."

  /// The message.
  public var errorDescription: String? { message }

  /// The message.
  public var description: String { message }
}

func grpcCode(status: Int) -> String {
  switch status {
  case 400: "InvalidArgument"
  case 401: "Unauthenticated"
  case 403: "PermissionDenied"
  case 404: "NotFound"
  case 409: "Aborted"
  case 429: "ResourceExhausted"
  case 499: "Cancelled"
  case 501: "Unimplemented"
  case 503: "Unavailable"
  case 504: "DeadlineExceeded"
  case 500...: "Internal"
  default: "Unknown"
  }
}
