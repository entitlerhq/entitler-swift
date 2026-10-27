import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let grantJSON = #"""
  {"id": "gr_1", "featureKey": "ai_credits", "value": {"limit": {"count": 5000}},
    "from": 1790000000, "until": 1792592000, "reason": "Ticket 4127",
    "grantedBy": {"type": "ACTOR_TYPE_KEY", "id": "key_1"}}
  """#

@Suite struct CompanyWriteTests {
  @Test func grantSendsTheValueAndNeverRetries() async throws {
    let api = FakeAPI([
      Answer(status: 503, body: refusal("Unavailable", nil)),
      Answer(body: #"{"grant": \#(grantJSON), "revision": 7}"#),
    ])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada")
    await #expect(throws: EntitlerError.self) {
      try await customer.grant("ai_credits", value: .amount(5_000), days: 30, reason: "Ticket 4127")
    }
    #expect(api.requests.count == 1)

    let result = try await customer.grant(
      "ai_credits", value: .amount(5_000), days: 30, expectedRevision: 6, currency: "aud")
    let sent = body(try #require(api.requests.last))
    #expect(api.requests.last?.url?.path == "/v1/customers/ada/grants")
    #expect((sent["value"] as? [String: Any])?["limit"] as? [String: Int] == ["count": 5000])
    #expect(sent["days"] as? Int == 30)
    #expect(sent["expectedRevision"] as? [String: Int] == ["value": 6])
    #expect(sent["currency"] as? String == "aud")
    #expect(result.revision == 7)
    #expect(result.grant.value == .amount(5000))
    #expect(result.grant.until == Date(timeIntervalSince1970: 1_792_592_000))
    #expect(result.grant.grantedBy == ChangedBy(type: OpenName(rawValue: "key"), id: "key_1"))
    #expect(result.grant.revokedBy == nil)
  }

  @Test func aGrantDropsTheCustomersKeptAnswers() async throws {
    let kept = Answer(headers: ["Cache-Control": "private, max-age=600"], body: switchCheck)
    let api = FakeAPI([kept, Answer(body: #"{"grant": \#(grantJSON), "revision": 7}"#), kept])
    let ada = try api.server().customer("ada")
    _ = try await ada.check("priority_support")
    _ = try await ada.grant("ai_credits", value: .amount(5_000))
    _ = try await ada.check("priority_support")

    #expect(api.requests.count == 3)
  }

  @Test func aGrantOutOfRangeIsRefusedBeforeAnyRequest() async throws {
    let api = FakeAPI([])
    let customer = try api.server().customer("ada")
    await #expect(throws: ArgumentError.self) {
      try await customer.grant("seats", value: .amount(-1))
    }
    await #expect(throws: ArgumentError.self) {
      try await customer.grant("seats", value: .on, days: 3_651)
    }
    await #expect(throws: ArgumentError.self) {
      try await customer.adjustMeter(of: "ai_credits", .setTo(-1))
    }
    #expect(api.requests.isEmpty)
  }

  @Test func aGrantAnsweredWithoutItsValueIsResponseInvalid() async throws {
    for value in ["", #""value": {},"#] {
      let answer = grantJSON.replacingOccurrences(
        of: #""value": {"limit": {"count": 5000}},"#, with: value)
      let api = FakeAPI([Answer(body: #"{"grant": \#(answer), "revision": 7}"#)])
      do {
        _ = try await api.server().customer("ada").grant("ai_credits", value: .amount(5_000))
        Issue.record("Expected a failure.")
      } catch EntitlerError.api(let error) {
        #expect(error.reason == .responseInvalid)
        #expect(error.underlyingError is AnswerMismatch)
      }
    }
  }

  @Test func revokeGrantRetriesOnlyWithoutARevision() async throws {
    let revoked = Answer(
      body:
        #"{"grant": \#(grantJSON.replacingOccurrences(of: #""reason": "Ticket 4127""#, with: #""reason": "", "revokedAt": 1790000500, "revokeReason": "Refunded""#)), "revision": 8, "changed": true}"#
    )
    let unavailable = Answer(status: 503, body: refusal("Unavailable", nil))
    let api = FakeAPI([unavailable, revoked, unavailable])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada")
    let result = try await customer.revokeGrant("gr_1", reason: "Refunded")
    await #expect(throws: EntitlerError.self) {
      try await customer.revokeGrant("gr_1", expectedRevision: 8)
    }

    #expect(api.requests.map(\.url?.path).first == "/v1/customers/ada/grants/gr_1:revoke")
    #expect(api.requests.count == 3)
    #expect(result.changed)
    #expect(result.grant.reason == "")
    #expect(result.grant.revokeReason == "Refunded")
  }

  @Test func setTrackSendsTheTrackOrNothingForTheDefault() async throws {
    let assignment = #"""
      {"assignment": {"customerId": "cu_1", "externalId": "ada", "trackId": "tr_2",
        "previousTrackId": null, "source": "ASSIGNMENT_SOURCE_SERVER",
        "money": "CUSTOMER_MONEY_TEST", "revision": 9}, "changed": true, "endedTestHoldings": 1}
      """#
    let api = FakeAPI([Answer(body: assignment), Answer(body: assignment)])
    let customer = try api.server().customer("ada")
    let moved = try await customer.setTrack("tr_2")
    _ = try await customer.setTrack(nil)

    #expect(api.requests.first?.httpMethod == "PUT")
    #expect(api.requests.first?.url?.path == "/v1/customers/ada/track")
    #expect(body(api.requests[0])["trackId"] as? String == "tr_2")
    #expect(body(api.requests[1]).isEmpty)
    #expect(moved.track == "tr_2")
    #expect(moved.previousTrack == nil)
    #expect(moved.source.rawValue == "server")
    #expect(moved.money.rawValue == "test")
    #expect(moved.endedTestHoldings == 1)
  }

  @Test func adjustMeterRetriesOnlyWithAKey() async throws {
    let unavailable = Answer(status: 503, body: refusal("Unavailable", nil))
    let adjusted = Answer(body: usage("ADJUSTED", amount: 0))
    let api = FakeAPI([unavailable, unavailable, adjusted])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada")
    await #expect(throws: EntitlerError.self) {
      try await customer.adjustMeter(of: "ai_credits", .changeBy(-5))
    }
    let result = try await customer.adjustMeter(
      of: Feature<Metered>("ai_credits"), .setTo(0), reason: "Reset", idempotencyKey: "adj-1")

    #expect(api.requests.count == 3)
    #expect(api.requests[0].url?.path == "/v1/customers/ada/meters/ai_credits:adjust")
    #expect(body(api.requests[0])["changeBy"] as? Int == -5)
    #expect(body(api.requests[0])["setTo"] == nil)
    #expect(body(api.requests[2])["setTo"] as? Int == 0)
    #expect(body(api.requests[2])["idempotencyKey"] as? String == "adj-1")
    #expect(result.outcome.rawValue == "adjusted")
  }

  @Test func cancelUsageCancelsTheReport() async throws {
    let api = FakeAPI([Answer(body: usage("CANCELLED", amount: 3))])
    let result = try await api.server().customer("ada").cancelUsage("us_1", reason: "Duplicate")

    #expect(api.requests.first?.url?.path == "/v1/customers/ada/usage/us_1:cancel")
    #expect(body(try #require(api.requests.first))["reason"] as? String == "Duplicate")
    #expect(result.outcome.rawValue == "cancelled")
  }
}
