import Foundation
import Testing

@testable import Entitler

let customerRecordJSON = #"""
  {"id": "cu_1", "projectId": "pj_1", "environmentId": "en_1", "externalId": "ada",
    "name": "Ada", "email": "ada@example.com",
    "attributes": [{"key": "region", "value": "au"}],
    "money": "CUSTOMER_MONEY_TEST", "revision": 4, "createdAt": 1790000000, "updatedAt": 1790000100}
  """#

@Suite struct CustomerTests {
  @Test func registeringSendsTheDetailsAndAnswersTheRecord() async throws {
    let api = FakeAPI([Answer(body: #"{"created": true, "customer": \#(customerRecordJSON)}"#)])
    let registered = try await api.server().customer("ada").register(
      name: "Ada", email: "ada@example.com", attributes: ["region": "au", "plan_hint": nil],
      visitor: "vi_1")

    let request = try #require(api.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/v1/customers/ada")
    let sent = body(request)
    #expect(sent["name"] as? String == "Ada")
    #expect(sent["visitorId"] as? String == "vi_1")
    let attributes = try #require(sent["attributes"] as? [[String: String]])
    #expect(attributes == [["key": "plan_hint"], ["key": "region", "value": "au"]])
    #expect(registered.created)
    #expect(registered.customerID == "cu_1")
    #expect(registered.attributes == ["region": "au"])
    #expect(registered.money.rawValue == "test")
    #expect(registered.updatedAt == Date(timeIntervalSince1970: 1_790_000_100))
  }

  @Test func detailsAndUpdateReadAndChangeTheRecord() async throws {
    let api = FakeAPI([
      Answer(body: #"{"customer": \#(customerRecordJSON)}"#),
      Answer(body: #"{"customer": \#(customerRecordJSON)}"#),
    ])
    let ada = try api.server().customer("ada")
    #expect(try await ada.details().name == "Ada")
    try await ada.update(email: "ada@example.org")

    #expect(api.requests.map(\.httpMethod) == ["GET", "PATCH"])
    #expect(api.requests[0].httpBody == nil)
    #expect(body(api.requests[1]).keys.sorted() == ["email"])
  }

  @Test func anUpdateIsNotRetried() async throws {
    let api = FakeAPI([Answer(status: 503, body: refusal("Unavailable", nil))])
    await #expect(throws: EntitlerError.self) {
      try await api.server().customer("ada").update(name: "Ada")
    }
    #expect(api.requests.count == 1)
  }

  @Test func erasingIsRetriedAfterALostAnswer() async throws {
    let api = FakeAPI([Answer(failure: .networkConnectionLost), Answer(body: #"{"erased": 1}"#)])
    try await api.server().customer("ada").erase()

    #expect(
      api.requests.map(\.url?.path) == ["/v1/customers/ada:erase", "/v1/customers/ada:erase"])
    #expect(api.requests.allSatisfy { $0.httpMethod == "POST" })
  }

  @Test func aTokenNamesItsScopesAndHidesItself() async throws {
    let api = FakeAPI([
      Answer(
        body: #"""
          {"token": "ctk_secret", "tokenId": "tk_1", "customerId": "cu_1", "expiresAt": 1790003600,
            "scopes": ["CUSTOMER_TOKEN_SCOPE_ENTITLEMENTS_READ", "CUSTOMER_TOKEN_SCOPE_USAGE_WRITE"]}
          """#)
    ])
    let token = try await api.server().customer("ada").token(
      scopes: [.entitlementsRead, .usageWrite], ttlSeconds: 600)

    let sent = body(try #require(api.requests.first))
    #expect(
      sent["scopes"] as? [String] == [
        "CUSTOMER_TOKEN_SCOPE_ENTITLEMENTS_READ", "CUSTOMER_TOKEN_SCOPE_USAGE_WRITE",
      ])
    #expect(sent["lifetimeSeconds"] as? Int == 600)
    #expect(token.token == "ctk_secret")
    #expect(token.scopes == [.entitlementsRead, .usageWrite])
    #expect(!"\(token)".contains("ctk_secret"))
    #expect(!String(reflecting: token).contains("ctk_secret"))
  }

  @Test func aTokenLifetimeOutsideTheAPIsBoundsIsRefused() async throws {
    let api = FakeAPI([])
    let ada = try api.server().customer("ada")
    for ttl in [59, 3601] {
      await #expect(throws: ArgumentError.self) { try await ada.token(ttlSeconds: ttl) }
    }
    #expect(api.requests.isEmpty)
  }

  @Test func theServerHasNoSignedInCustomer() throws {
    #expect(throws: ArgumentError.self) { try FakeAPI([]).server().customer("me") }
  }
}
