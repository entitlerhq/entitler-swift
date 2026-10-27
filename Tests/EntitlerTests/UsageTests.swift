import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

func usage(
  _ outcome: String, amount: Int64 = 500, holdID: String? = nil, refusal: String? = nil,
  extra: String = ""
) -> String {
  let hold = holdID.map { #", "holdId": "\#($0)", "expiresAtMs": 1790000300000"# } ?? ""
  let refused = refusal.map { #", "refusal": "USAGE_REFUSAL_\#($0)""# } ?? ""
  return #"""
    {"tracked": {
      "asOf": 1790000000,
      "customer": {"externalId": "ada"},
      "entitlement": {"featureKey": "ai_credits", "kind": "ENTITLED_FEATURE_KIND_METERED",
        "entitled": true, "value": {"metered": {"count": 1000}}, "sources": [], "upgrades": [],
        "meter": {"used": 250, "held": 0, "banked": 0, "remaining": {"count": 750}}},
      "usage": {"outcome": "USAGE_OUTCOME_\#(outcome)", "mode": "USAGE_MODE_GATE",
        "amount": \#(amount), "meterChange": 0, "overBy": 0, "late": false,
        "replayed": false\#(hold)\#(refused)\#(extra)}
    }}
    """#
}

func body(_ request: URLRequest) -> [String: Any] {
  (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

@Suite struct UsageTests {
  let aiCredits = Feature<Metered>("ai_credits")

  @Test func recordingUsageSendsTheReportAndReadsTheAnswer() async throws {
    let api = FakeAPI([
      Answer(
        body: usage(
          "RECORDED", amount: 3, extra: #", "usageId": "us_1", "occurredAtMs": 1789999999500"#))
    ])
    let result = try await api.server().customer("ada").recordUsage(
      of: aiCredits, amount: 3, idempotencyKey: "run-42", mode: .observe,
      occurredAt: Date(timeIntervalSince1970: 1_789_999_999.5))

    let request = try #require(api.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/v1/customers/ada/usage")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let sent = body(request)
    #expect(sent["featureKey"] as? String == "ai_credits")
    #expect(sent["amount"] as? Int == 3)
    #expect(sent["idempotencyKey"] as? String == "run-42")
    #expect(sent["mode"] as? String == "USAGE_MODE_OBSERVE")
    #expect(sent["occurredAtMs"] as? Int == 1_789_999_999_500)
    #expect(sent["register"] == nil)
    #expect(result.outcome == .recorded)
    #expect(result.id == "us_1")
    #expect(result.mode == .gate)
    #expect(result.occurredAt == Date(timeIntervalSince1970: 1_789_999_999.5))
    #expect(result.meter?.remaining == .amount(750))
    #expect(result.customer == "ada")
  }

  @Test func aWriteIsRetriedAndAFailureCarriesItsIdempotencyKey() async throws {
    let api = FakeAPI([
      Answer(failure: .networkConnectionLost),
      Answer(status: 503, body: refusal("Unavailable", nil)),
      Answer(status: 503, body: refusal("Unavailable", nil)),
    ])
    await #expect {
      try await api.server().customer("ada").recordUsage(
        of: aiCredits, amount: 1, idempotencyKey: "run-1")
    } throws: { error in
      guard case EntitlerError.api(let failure) = error else { return false }
      return failure.idempotencyKey == "run-1"
    }
    #expect(api.requests.count == 3)
  }

  @Test func anIdempotencyKeyMustBePrintableASCII() async throws {
    let api = FakeAPI([])
    let customer = try api.server().customer("ada")
    for key in ["", " lead", "trail ", "tab\t", String(repeating: "k", count: 201), "café"] {
      await #expect(throws: ArgumentError.self) {
        try await customer.recordUsage(of: aiCredits, amount: 1, idempotencyKey: key)
      }
    }
    await #expect(throws: ArgumentError.self) {
      try await customer.startHold(
        of: aiCredits, amount: 1, idempotencyKey: String(repeating: "k", count: 194))
    }
    #expect(api.requests.isEmpty)
  }

  @Test func aRefusedHoldThrowsWithTheAnswer() async throws {
    let api = FakeAPI([Answer(body: usage("REFUSED", refusal: "OVER_ALLOWANCE"))])
    await #expect {
      try await api.server().customer("ada").startHold(
        of: aiCredits, amount: 500, idempotencyKey: "m-1")
    } throws: { error in
      guard case EntitlerError.usageRefused(let refused) = error else { return false }
      return refused.result.refusal == .overAllowance
    }
  }

  @Test func aHoldWhoseKeyWasAlreadySettledIsAReplay() async throws {
    let api = FakeAPI([Answer(body: usage("SETTLED", holdID: "ho_1"))])
    await #expect {
      try await api.server().customer("ada").startHold(
        of: aiCredits, amount: 500, idempotencyKey: "m-1")
    } throws: { error in
      guard case EntitlerError.usageReplayed = error else { return false }
      return true
    }
  }

  @Test func aDuplicateIsAnotherCallersHoldUnlessOurOwnRetryMetIt() async throws {
    let first = FakeAPI([Answer(body: usage("DUPLICATE", holdID: "ho_1"))])
    let theirs = try await first.server().customer("ada").startHold(
      of: aiCredits, amount: 500, idempotencyKey: "m-1")
    #expect(theirs.isDuplicate)

    let retried = FakeAPI([
      Answer(status: 503, body: refusal("Unavailable", nil)),
      Answer(body: usage("DUPLICATE", holdID: "ho_1")),
    ])
    let ours = try await retried.server().customer("ada").startHold(
      of: aiCredits, amount: 500, idempotencyKey: "m-1")
    #expect(!ours.isDuplicate)
  }

  @Test func withHoldSettlesWhatTheWorkUsedAndRecordsTheExcess() async throws {
    let api = FakeAPI([
      Answer(body: usage("HELD", holdID: "ho_1")),
      Answer(body: usage("SETTLED", holdID: "ho_1")),
      Answer(body: usage("RECORDED", amount: 20)),
    ])
    let customer = try api.server().customer("ada")
    let summary = try await customer.withHold(
      of: aiCredits, amount: 500, idempotencyKey: "summary-81", ttlSeconds: 600
    ) { hold in
      #expect(hold.id == "ho_1")
      #expect(!hold.isDuplicate)
      try hold.use(520)
      return "summary"
    }

    #expect(summary == "summary")
    let requests = api.requests
    #expect(
      requests.map(\.url?.path) == [
        "/v1/customers/ada/usage/holds", "/v1/customers/ada/usage/holds/ho_1:settle",
        "/v1/customers/ada/usage",
      ])
    #expect(body(requests[0])["ttlSeconds"] as? Int == 600)
    #expect(body(requests[1])["amount"] as? Int == 500)
    #expect(body(requests[2])["amount"] as? Int == 20)
    #expect(body(requests[2])["idempotencyKey"] as? String == "summary-81:excess")
    #expect(body(requests[2])["mode"] as? String == "USAGE_MODE_OBSERVE")
  }

  @Test func workThatFailsBeforeReportingReleasesTheHold() async throws {
    struct Failed: Error {}
    let api = FakeAPI([
      Answer(body: usage("HELD", holdID: "ho_1")),
      Answer(body: usage("RELEASED", holdID: "ho_1")),
    ])
    await #expect(throws: Failed.self) {
      try await api.server().customer("ada").withHold(
        of: aiCredits, amount: 500, idempotencyKey: "m-1"
      ) { _ in throw Failed() }
    }
    #expect(api.requests.last?.httpMethod == "DELETE")
    #expect(api.requests.last?.url?.path == "/v1/customers/ada/usage/holds/ho_1")
  }

  @Test func aCancelledCallRunsNoWork() async throws {
    let api = FakeAPI([
      Answer(body: usage("HELD", holdID: "ho_1")),
      Answer(body: usage("RELEASED", holdID: "ho_1")),
    ])
    let customer = try api.server().customer("ada")
    let ran = LockedValue(false)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await customer.withHold(of: aiCredits, amount: 500, idempotencyKey: "m-1") { _ in
        ran.update { $0 = true }
      }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!ran.read())
  }

  @Test func anExpiredHoldRecordsTheWholeAmountAsExcess() async throws {
    let api = FakeAPI([
      Answer(body: usage("HELD", holdID: "ho_1")),
      Answer(status: 409, body: refusal("FailedPrecondition", "HOLD_EXPIRED")),
      Answer(body: usage("RECORDED", amount: 120)),
    ])
    let hold = try await api.server().customer("ada").startHold(
      of: aiCredits, amount: 500, idempotencyKey: "m-1")
    try hold.use(120)
    let result = try await hold.finish()

    #expect(result.outcome == .recorded)
    #expect(body(api.requests[2])["amount"] as? Int == 120)
    #expect(body(api.requests[2])["idempotencyKey"] as? String == "m-1:excess")
    #expect(try await hold.release().outcome == .recorded)
    #expect(api.requests.count == 3)
  }

  @Test func aFailedSettlementKeepsTheWorksResult() async throws {
    let api = FakeAPI([
      Answer(body: usage("HELD", holdID: "ho_1")),
      Answer(status: 400, body: refusal("InvalidArgument", "AMOUNT_INVALID")),
    ])
    await #expect {
      try await api.server().customer("ada").withHold(
        of: aiCredits, amount: 500, idempotencyKey: "m-1"
      ) { hold in
        try hold.use(80)
        return "output"
      }
    } throws: { error in
      guard case EntitlerError.usageSettlement(let failure) = error else { return false }
      return failure.result as? String == "output" && !failure.settled && failure.amount == 80
        && failure.excess == nil && failure.excessKey == "m-1:excess"
    }
  }
}
