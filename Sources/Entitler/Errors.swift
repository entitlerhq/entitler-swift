import Foundation

/// A failure the SDK raises.
///
/// Catch one kind with a pattern:
///
/// ```swift
/// do {
///   try await customer.recordUsage(of: Features.aiCredits, amount: 3)
/// } catch EntitlerError.api(let error) where error.code == .customerNotFound {
///   try await customer.register()
/// }
/// ```
///
/// Cancelling the task surfaces `CancellationError`, and an invalid argument surfaces
/// ``ArgumentError``; neither is an `EntitlerError`.
public enum EntitlerError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The API answered with a status other than 2xx.
  case api(APIError)
  /// No answer arrived: DNS, TLS, or a refused or reset connection.
  case connection(ConnectionError)
  /// An attempt took longer than its timeout.
  case timeout(TimeoutError)
  /// A token provider failed or answered an unusable token.
  case token(TokenError)
  /// An offline snapshot failed verification.
  case snapshot(SnapshotError)
  /// ``Customer/withHold(of:amount:ttlSeconds:idempotencyKey:timeout:_:)`` was refused its hold.
  case usageRefused(UsageResult)

  /// The message of the error this case carries.
  public var errorDescription: String? { description }

  /// The message of the error this case carries.
  public var description: String {
    switch self {
    case .api(let error): error.description
    case .connection(let error): error.message
    case .timeout(let error): error.message
    case .token(let error): error.message
    case .snapshot(let error): error.message
    case .usageRefused(let answer):
      "Entitler refused the hold on \(answer.feature) (\(answer.refusal?.rawValue ?? "refused"))."
    }
  }

  var isUnreachable: Bool {
    switch self {
    case .connection, .timeout: true
    case .api(let error): error.status == 429 || error.status >= 500
    default: false
    }
  }

  func withHoldID(_ holdID: String) -> EntitlerError {
    switch self {
    case .api(var error):
      error.holdID = holdID
      return .api(error)
    case .connection(var error):
      error.holdID = holdID
      return .connection(error)
    case .timeout(var error):
      error.holdID = holdID
      return .timeout(error)
    case .token(var error):
      error.holdID = holdID
      return .token(error)
    default:
      return self
    }
  }
}

/// The API answered with a status other than 2xx.
public struct APIError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible {
  /// The HTTP status.
  public let status: Int
  /// The error code from the answer, or ``ErrorCode/httpError`` when it had none.
  public let code: ErrorCode
  /// The message from the answer, fit to show a person.
  public let message: String
  /// The `x-request-id` header, for Entitler's support.
  public let requestID: String?
  /// How long the API asked the caller to wait before trying again, from `Retry-After`.
  public let retryAfter: TimeInterval?
  /// The idempotency key the request sent, to repeat the call later with the same key.
  public let idempotencyKey: String?
  /// The hold a failed settlement was for, so the app can settle it again.
  public internal(set) var holdID: String?
  /// With `402 payment_required`: the payment a plan change waits on.
  public let payment: Payment?
  /// With `409 listing_gaps`: the gaps a rollout would leave.
  public let listingGaps: [ListingGap]
  /// With `409 listing_invalid`: the listings whose price fails the checks.
  public let listingProblems: [ListingProblem]

  /// The message from the answer.
  public var errorDescription: String? { message }

  /// The status, code and message.
  public var description: String { "\(status) \(code.rawValue): \(message)" }
}

/// No answer arrived from Entitler.
public struct ConnectionError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The error the HTTP client raised.
  public let underlyingError: any Error
  /// The idempotency key the request sent, to repeat the call later with the same key.
  public let idempotencyKey: String?
  /// The hold a failed settlement was for, so the app can settle it again.
  public internal(set) var holdID: String?

  /// A sentence saying Entitler could not be reached.
  public var message: String { "Entitler could not be reached: \(underlyingError.localizedDescription)" }

  /// A sentence saying Entitler could not be reached.
  public var errorDescription: String? { message }

  /// A sentence saying Entitler could not be reached.
  public var description: String { message }
}

/// An attempt took longer than its timeout.
public struct TimeoutError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// The timeout the attempt exceeded, in seconds.
  public let timeout: TimeInterval
  /// The idempotency key the request sent, to repeat the call later with the same key.
  public let idempotencyKey: String?
  /// The hold a failed settlement was for, so the app can settle it again.
  public internal(set) var holdID: String?

  /// A sentence naming the timeout.
  public var message: String { "Entitler did not answer within \(timeout.formatted()) seconds." }

  /// A sentence naming the timeout.
  public var errorDescription: String? { message }

  /// A sentence naming the timeout.
  public var description: String { message }
}

/// A token provider failed or answered an unusable token. It never holds the token.
public struct TokenError: Error, Sendable, LocalizedError, CustomStringConvertible {
  /// What went wrong.
  public let message: String
  /// The error the provider threw, if it threw one.
  public let underlyingError: (any Error)?
  /// The hold a failed settlement was for, so the app can settle it again.
  public internal(set) var holdID: String?

  /// What went wrong.
  public var errorDescription: String? { message }

  /// What went wrong.
  public var description: String { message }
}

/// An offline snapshot failed verification. No request was made.
public struct SnapshotError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible {
  /// Why a snapshot failed verification.
  public enum Code: String, Sendable, Hashable {
    /// The snapshot is malformed, signed by another key, changed, or for someone else.
    case invalid = "snapshot_invalid"
    /// The snapshot has expired.
    case expired = "snapshot_expired"
  }

  /// Why the snapshot failed verification.
  public let code: Code
  /// What went wrong, fit to show a developer.
  public let message: String

  /// What went wrong.
  public var errorDescription: String? { message }

  /// What went wrong.
  public var description: String { message }
}

/// An argument the SDK cannot use, raised before any request.
public struct ArgumentError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible {
  /// What to pass instead.
  public let message: String

  /// What to pass instead.
  public var errorDescription: String? { message }

  /// What to pass instead.
  public var description: String { message }
}

/// The code of an ``APIError``, extensible like `Notification.Name`: an unknown code is kept as it is.
public struct ErrorCode: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
  /// The code as the API sends it, such as `customer_not_found`.
  public let rawValue: String

  /// Creates a code from the API's string.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The code as the API sends it.
  public var description: String { rawValue }

  /// The organisation's allowance is used up.
  public static let allowanceReached = ErrorCode(rawValue: "allowance_reached")
  /// The connection is already made.
  public static let alreadyConnected = ErrorCode(rawValue: "already_connected")
  /// The credential cannot read at another instant.
  public static let asOfNotAllowed = ErrorCode(rawValue: "as_of_not_allowed")
  /// The request body is too large.
  public static let bodyTooLarge = ErrorCode(rawValue: "body_too_large")
  /// The browser origin is not allowed for the key.
  public static let browserNotAllowed = ErrorCode(rawValue: "browser_not_allowed")
  /// A cap, such as live grants per customer, is reached.
  public static let capReached = ErrorCode(rawValue: "cap_reached")
  /// A carried-forward change conflicts.
  public static let carryForwardConflict = ErrorCode(rawValue: "carry_forward_conflict")
  /// The catalogue is not empty.
  public static let catalogueNotEmpty = ErrorCode(rawValue: "catalogue_not_empty")
  /// The change is locked.
  public static let changeLocked = ErrorCode(rawValue: "change_locked")
  /// The request needs a change.
  public static let changeRequired = ErrorCode(rawValue: "change_required")
  /// The connection is in use.
  public static let connectionInUse = ErrorCode(rawValue: "connection_in_use")
  /// The connection's mode does not allow the request.
  public static let connectionMode = ErrorCode(rawValue: "connection_mode")
  /// Several connections list the plan: name one.
  public static let connectionRequired = ErrorCode(rawValue: "connection_required")
  /// The connection's key cannot be read.
  public static let connectionUnreadable = ErrorCode(rawValue: "connection_unreadable")
  /// The route refuses this kind of credential, such as a customer token on a server route.
  public static let credentialNotAllowed = ErrorCode(rawValue: "credential_not_allowed")
  /// The customer is not registered.
  public static let customerNotFound = ErrorCode(rawValue: "customer_not_found")
  /// The email address is taken.
  public static let emailTaken = ErrorCode(rawValue: "email_taken")
  /// The email address is not confirmed.
  public static let emailUnconfirmed = ErrorCode(rawValue: "email_unconfirmed")
  /// An experiment is running.
  public static let experimentRunning = ErrorCode(rawValue: "experiment_running")
  /// No feature has that key.
  public static let featureNotFound = ErrorCode(rawValue: "feature_not_found")
  /// The hold expired before it was settled.
  public static let holdExpired = ErrorCode(rawValue: "hold_expired")
  /// The hold was released.
  public static let holdReleased = ErrorCode(rawValue: "hold_released")
  /// The hold was settled with another amount.
  public static let holdSettled = ErrorCode(rawValue: "hold_settled")
  /// The SDK's own code for an answer that carried no error code.
  public static let httpError = ErrorCode(rawValue: "http_error")
  /// The request needs an idempotency key.
  public static let idempotencyKeyRequired = ErrorCode(rawValue: "idempotency_key_required")
  /// The idempotency key was used for a different request.
  public static let idempotencyMismatch = ErrorCode(rawValue: "idempotency_mismatch")
  /// Entitler failed on its side.
  public static let `internal` = ErrorCode(rawValue: "internal")
  /// The amount is not allowed.
  public static let invalidAmount = ErrorCode(rawValue: "invalid_amount")
  /// The request body is not valid.
  public static let invalidBody = ErrorCode(rawValue: "invalid_body")
  /// The idempotency key is not 1 to 200 printable ASCII characters.
  public static let invalidIdempotencyKey = ErrorCode(rawValue: "invalid_idempotency_key")
  /// The instant the usage occurred is too far back, ahead, or before the customer registered.
  public static let invalidOccurredAt = ErrorCode(rawValue: "invalid_occurred_at")
  /// The path is not valid.
  public static let invalidPath = ErrorCode(rawValue: "invalid_path")
  /// The last environment cannot be removed.
  public static let lastEnvironment = ErrorCode(rawValue: "last_environment")
  /// The organisation's plan does not allow the request.
  public static let limitReached = ErrorCode(rawValue: "limit_reached")
  /// A rollout would leave listing gaps.
  public static let listingGaps = ErrorCode(rawValue: "listing_gaps")
  /// A listing's price fails the checks.
  public static let listingInvalid = ErrorCode(rawValue: "listing_invalid")
  /// The method is not allowed on the route.
  public static let methodNotAllowed = ErrorCode(rawValue: "method_not_allowed")
  /// Nothing was found.
  public static let notFound = ErrorCode(rawValue: "not_found")
  /// The plan is not listed.
  public static let notListed = ErrorCode(rawValue: "not_listed")
  /// Usage was sent for a feature that is not metered.
  public static let notMetered = ErrorCode(rawValue: "not_metered")
  /// The change is not on a self-serve path from the customer's plans.
  public static let notSelfServe = ErrorCode(rawValue: "not_self_serve")
  /// A plan change waits on a payment; see ``APIError/payment``.
  public static let paymentRequired = ErrorCode(rawValue: "payment_required")
  /// The request needs a person.
  public static let personRequired = ErrorCode(rawValue: "person_required")
  /// The payment provider still bills the plan.
  public static let planStillBilled = ErrorCode(rawValue: "plan_still_billed")
  /// The payment provider's account changed.
  public static let providerAccountChanged = ErrorCode(rawValue: "provider_account_changed")
  /// The payment provider charged only part of the change.
  public static let providerPartial = ErrorCode(rawValue: "provider_partial")
  /// Publishing failed.
  public static let publicationFailed = ErrorCode(rawValue: "publication_failed")
  /// Too many requests; see ``APIError/retryAfter``.
  public static let rateLimited = ErrorCode(rawValue: "rate_limited")
  /// The change needs a review.
  public static let reviewRequired = ErrorCode(rawValue: "review_required")
  /// The credential lacks the scope the route needs.
  public static let scopeRequired = ErrorCode(rawValue: "scope_required")
  /// Sign-ups are closed.
  public static let signUpsClosed = ErrorCode(rawValue: "sign_ups_closed")
  /// The request no longer matches the state, or no payment provider can take it.
  public static let stale = ErrorCode(rawValue: "stale")
  /// The switch is in use.
  public static let switchInUse = ErrorCode(rawValue: "switch_in_use")
  /// The request needs a switch turned on.
  public static let switchNeeded = ErrorCode(rawValue: "switch_needed")
  /// The switch is off.
  public static let switchOff = ErrorCode(rawValue: "switch_off")
  /// The project has too many customers.
  public static let tooManyCustomers = ErrorCode(rawValue: "too_many_customers")
  /// The track is closed.
  public static let trackClosed = ErrorCode(rawValue: "track_closed")
  /// The credential is not valid now.
  public static let unauthorised = ErrorCode(rawValue: "unauthorised")
  /// Entitler or a provider is unavailable for now; see ``APIError/retryAfter``.
  public static let unavailable = ErrorCode(rawValue: "unavailable")
}
