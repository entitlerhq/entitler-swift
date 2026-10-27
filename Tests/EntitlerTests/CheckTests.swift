import Foundation
import Testing

@testable import Entitler

@Suite struct CheckTests {
  @Test func checkSendsTheRouteAndDecodesTheAnswer() async throws {
    let api = FakeAPI([Answer(body: switchCheck)])
    let check = try await api.server().customer("ada").check("priority_support")

    let request = try #require(api.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(
      request.url?.absoluteString
        == "https://api.entitler.app/v1/customers/ada/entitlements/priority_support")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(
      request.value(forHTTPHeaderField: "User-Agent") == "entitler-swift/\(entitlerSDKVersion)")

    #expect(check.entitled)
    #expect(check.key == "priority_support")
    #expect(check.type == .switch)
    #expect(check.value == .on)
    #expect(check.meter == nil)
    #expect(check.customer == "ada")
    #expect(check.customerID == "cu_1")
    #expect(check.asOf == Date(timeIntervalSince1970: 1_790_000_000))
    #expect(
      check.served
        == Served(
          track: ServedTrack(id: "tr_1", name: "All customers"),
          source: .release(id: "re_1", number: 12)))
    #expect(
      check.sources == [
        .plan(
          PlanSource(
            planID: "pl_1", plan: "pro", name: "Pro", product: "pr_1", version: 3, byDefault: false,
            value: .on, markets: nil, through: nil)),
        .grant(
          GrantSource(
            grant: "gr_1", until: Date(timeIntervalSince1970: 1_790_086_400), value: nil,
            markets: nil, through: nil)),
      ])
    #expect(check.upgrades.map(\.plan) == ["team"])
    #expect(check.upgrades.first?.kind.rawValue == "plan")
    #expect(check.upgrades.first?.move.rawValue == "upgrade")
    #expect(check.upgrades.first?.action.rawValue == "buy")
    #expect(!check.stale)
  }

  @Test func aMeteredFeatureCheckCarriesItsMeter() async throws {
    let api = FakeAPI([Answer(body: meteredCheck)])
    let check = try await api.server().customer("ada").check(Feature<Metered>("ai_credits"))

    #expect(
      check.meter
        == Meter(
          used: 250, held: 50, banked: 0, remaining: .amount(700),
          resetsAt: Date(timeIntervalSince1970: 1_790_500_000)))
    #expect(check.value == .amount(1_000))
    #expect(check.nextChangeAt == Date(timeIntervalSince1970: 1_790_500_000))
    #expect(check.served.source == .nothing)
  }

  @Test func aMoneyFeatureCarriesItsScaleCurrencyAndMarkets() async throws {
    let api = FakeAPI([
      Answer(
        body: #"""
          {"asOf": 1790000000, "customer": {"externalId": "ada"}, "served": {"nothing": {}},
            "entitlement": {"featureKey": "spend", "kind": "ENTITLED_FEATURE_KIND_METERED",
              "entitled": true, "decimals": 2, "currency": "aud",
              "value": {"money": {"limits": [{"marketId": "mk_au", "limit": {"count": 5000}},
                {"marketId": "mk_us", "limit": {"unlimited": {}}}]}},
              "sources": [{"plan": {"planId": "pl_1", "planKey": "pro", "planName": "Pro",
                "versionNumber": 3,
                "value": {"money": {"limits": [{"marketId": "mk_au", "limit": {"count": 5000}}]}}}}],
              "upgrades": [],
              "meter": {"used": 1250, "held": 0, "banked": 0, "remaining": {"count": 3750}}}}
          """#)
    ])
    let check = try await api.server().customer("ada").check("spend")

    #expect(check.value == .amount(0))
    #expect(check.markets == ["mk_au": .amount(5000), "mk_us": .unlimited])
    #expect(check.decimals == 2)
    #expect(check.currency == "aud")
    guard case .plan(let plan) = check.sources.first else {
      Issue.record("Expected a plan source.")
      return
    }
    #expect(plan.markets == ["mk_au": .amount(5000)])
  }

  @Test func aFeatureThatIsNotMoneyHasNoMarketsOrCurrency() async throws {
    let api = FakeAPI([Answer(body: switchCheck)])
    let check = try await api.server().customer("ada").check("priority_support")

    #expect(check.markets == nil)
    #expect(check.decimals == 0)
    #expect(check.currency == nil)
  }

  @Test func aFeatureDeclaredAsAnotherKindIsRefused() async throws {
    let api = FakeAPI([Answer(body: switchCheck)])
    await #expect(throws: ArgumentError.self) {
      try await api.server().customer("ada").check(Feature<Metered>("priority_support"))
    }
  }

  @Test func entitlementsListsEveryFeature() async throws {
    let api = FakeAPI([Answer(body: entitlementList)])
    let entitlements = try await api.server().customer("ada").entitlements()

    #expect(api.requests.first?.url?.path == "/v1/customers/ada/entitlements")
    #expect(entitlements.map(\.key) == ["priority_support", "seats", "collaboration"])
    #expect(entitlements.has("priority_support"))
    #expect(!entitlements.has("collaboration"))
    #expect(!entitlements.has("missing"))
    #expect(entitlements["seats"]?.value == .unlimited)
    #expect(entitlements["collaboration"]?.value == .amount(0))
    #expect(entitlements["collaboration"]?.sources == [.group(features: ["seats"])])
    #expect(entitlements.served.source == .change(id: "ch_1"))
  }

  @Test func pathSegmentsAreEncodedAndAsOfIsSentInSeconds() async throws {
    let api = FakeAPI([Answer(body: switchCheck)])
    _ = try await api.server().customer("team/ada b").check(
      "priority_support", asOf: Date(timeIntervalSince1970: 1_790_000_000.9))

    #expect(
      api.requests.first?.url?.absoluteString
        == "https://api.entitler.app/v1/customers/team%2Fada%20b/entitlements/priority_support?as_of=1790000000"
    )
  }

  @Test func blankAndDotOnlyIdsAreRefusedBeforeAnyRequest() async throws {
    let api = FakeAPI([])
    #expect(throws: ArgumentError.self) { try api.server().customer(" ") }
    await #expect(throws: ArgumentError.self) {
      try await api.server().customer("..").check("priority_support")
    }
    await #expect(throws: ArgumentError.self) {
      try await api.server().customer("ada").check("")
    }
    await #expect(throws: ArgumentError.self) {
      try await api.server().customer("ada").check(
        "priority_support", asOf: Date(timeIntervalSince1970: 1e30))
    }
    #expect(api.requests.isEmpty)
  }

  @Test func anAnswerWithoutARequiredFieldIsResponseInvalid() async throws {
    let api = FakeAPI([
      Answer(
        headers: ["ETag": "W/\"v1\"", "x-request-id": "rq_2"],
        body: #"{"asOf": 1790000000, "customer": {"externalId": "ada"}}"#)
    ])
    do {
      _ = try await api.server().customer("ada").check("priority_support")
      Issue.record("Expected a failure.")
    } catch EntitlerError.api(let error) {
      #expect(error.reason == .responseInvalid)
      #expect(error.underlyingError is AnswerMismatch)
      #expect(error.requestID == "rq_2")
    }
  }

  @Test func anEntitlementWithoutAFeatureKeyIsResponseInvalid() async throws {
    let api = FakeAPI([
      Answer(
        body: #"""
          {"asOf": 1790000000, "customer": {"externalId": "ada"}, "entitlement": {"entitled": true, "decimals": 0, "currency": "",
            "kind": "ENTITLED_FEATURE_KIND_SWITCH", "sources": [], "upgrades": []}}
          """#)
    ])
    do {
      _ = try await api.server().customer("ada").check("priority_support")
      Issue.record("Expected a failure.")
    } catch EntitlerError.api(let error) {
      #expect(error.reason == .responseInvalid)
      guard case .keyNotFound(let key, _)? = error.underlyingError as? DecodingError else {
        Issue.record("Expected a missing key.")
        return
      }
      #expect(key.stringValue == "featureKey")
    }
  }

  @Test func isEntitledAnswersTheFallbackAndReportsTheFailure() async throws {
    let reported = LockedValue<[String]>([])
    let api = FakeAPI([Answer(status: 404, body: refusal("NotFound", "CUSTOMER_NOT_FOUND"))])
    let server = try api.server(
      options: EntitlerOptions(onError: { error in reported.update { $0.append("\(error)") } }))

    let customer = try server.customer("ada")
    let entitled = await customer.isEntitled(to: "priority_support", default: true)

    #expect(entitled)
    #expect(reported.read() == ["Entitler answered CUSTOMER_NOT_FOUND (HTTP 404)."])
  }

  @Test func aClosedClientRefusesCalls() async throws {
    let server = try FakeAPI([]).server()
    server.close()
    await #expect(throws: ClientClosedError.self) {
      try await server.customer("ada").check("priority_support")
    }
  }

  @Test func theDescriptionNeverShowsTheKey() throws {
    let server = try FakeAPI([]).server()
    #expect(server.description == "EntitlerServer(https://api.entitler.app)")
    #expect(!String(reflecting: server).contains("test-secret-key"))
  }
}
