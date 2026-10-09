import Foundation
import Testing

@testable import Entitler

@Suite struct ConstructionTests {
  @Test func blankCredentialsThrowArgumentErrors() {
    #expect(throws: ArgumentError(message: "Provide an Entitler API key from the dashboard.")) {
      try EntitlerServer(key: "  ")
    }
    #expect(throws: ArgumentError(message: "Provide a customer token minted by your server.")) {
      try EntitlerClient(token: "")
    }
    #expect(
      throws: ArgumentError(message: "Provide the identity token your sign-in provider issued.")
    ) {
      try EntitlerClient(key: "pk_1", identityToken: " ")
    }
    #expect(throws: ArgumentError(message: "Provide an Entitler API key from the dashboard.")) {
      try EntitlerClient(key: "", identityTokenProvider: { "x" })
    }
    #expect(throws: ArgumentError(message: "Provide the id your app uses for the customer.")) {
      try EntitlerServer(key: "sk").customer(" ")
    }
  }

  @Test func invalidVisitorAndAsOfThrow() throws {
    #expect(throws: ArgumentError(message: Messages.visitor)) {
      try EntitlerClient(token: "t", visitor: "short")
    }
    #expect(throws: ArgumentError(message: "Pass asOf as a valid date.")) {
      try EntitlerServer(
        key: "sk", options: EntitlerOptions(asOf: Date(timeIntervalSince1970: .nan)))
    }
    let client = try EntitlerClient(tokenProvider: { "x" }, visitor: "abcdefghijklmnop")
    #expect(client.visitor == "abcdefghijklmnop")
  }

  @Test func stringFormsNeverShowCredentials() throws {
    let server = try EntitlerServer(
      key: "sk_secret", options: EntitlerOptions(baseURL: URL(string: "https://x.test//")!))
    #expect(server.description == "EntitlerServer(https://x.test)")
    let client = try EntitlerClient(key: "pk_secret", identityToken: "id_secret")
    #expect(
      client.description == "EntitlerClient(in-app, identity token, https://api.entitler.dev)")
    let tokenClient = try EntitlerClient(token: "tok_secret")
    #expect(tokenClient.description.contains("customer token"))
    for value in [server as Any, client, tokenClient, try server.customer("u"), client.me] {
      var dumped = ""
      dump(value, to: &dumped)
      #expect(!dumped.contains("secret"))
      #expect(!String(reflecting: value).contains("secret"))
    }
    #expect(try server.customer("u").description == "ServerCustomer(u)")
    #expect(client.me.description == "SignedInCustomer(me)")
  }

  @Test func visitorsAreNewEachTimeAndValid() {
    let a = newVisitorID()
    #expect(a.count == 32)
    #expect(a.range(of: visitorIDPattern, options: .regularExpression) != nil)
    #expect(a != newVisitorID())
  }

  @Test func inAppClientGeneratesAndKeepsVisitor() throws {
    let client = try EntitlerClient(token: "t")
    #expect(client.visitor.range(of: visitorIDPattern, options: .regularExpression) != nil)
    #if canImport(Darwin)
      #expect(UserDefaults.standard.string(forKey: "entitler.visitor") == client.visitor)
      #expect(try EntitlerClient(token: "t").visitor == client.visitor)
    #endif
  }
}

@Suite struct RequestTests {
  @Test func checkSendsHeadersAndEncodesPath() async throws {
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let server = try api.server { $0.asOf = Date(timeIntervalSince1970: 1_782_898_200) }
    let check = try await api.run { try await server.customer("google:a/b c").check("sso") }
    #expect(check.entitled)
    #expect(check.value == .on)
    #expect(check.sources.first?.plan == "pro")
    let request = api.last
    #expect(request.method == "GET")
    #expect(request.path == "/customers/google%3Aa%2Fb%20c/entitlements/sso")
    #expect(request.header("Authorization") == "Bearer sk_test")
    #expect(request.header("Accept") == "application/json")
    #expect(request.header("Content-Type") == nil)
    #expect(request.header("Idempotency-Key") == nil)
    #expect(request.header("Entitler-Visitor") == nil)
    #expect(request.header("Entitler-As-Of") == "2026-07-01T09:30:00.000Z")
    #expect(request.header("User-Agent")?.hasPrefix("entitler-swift/0.1.0 ") == true)
  }

  @Test func encodingMatchesEncodeURIComponent() {
    #expect("aZ09-_.!~*'()".componentEncoded == "aZ09-_.!~*'()")
    #expect("a b/c?d&é".componentEncoded == "a%20b%2Fc%3Fd%26%C3%A9")
  }

  @Test func typedChecksDecodeMeteredAnswers() async throws {
    let api = FakeAPI { _ in .json(Fixture.meteredCheck) }
    let check = try await api.run {
      try await api.server().customer("u").check(Feature<Metered>("ai_credits"))
    }
    #expect(check.used == 10)
    #expect(check.held == 5)
    #expect(check.remaining == .amount(285))
    #expect(
      abs(
        try #require(check.resetsAt).timeIntervalSince(
          try #require(parseInstant("2026-10-18T19:30:35.544Z")))) < 0.001)
    #expect(check.track.name == "All customers")
    #expect(check.release == 2)
    #expect(check.environment.kind == .test)
    #expect(!check.stale)
  }

  @Test func blankFeatureIsAnArgumentError() async throws {
    let api = FakeAPI()
    await #expect(throws: ArgumentError(message: "Name the feature by its key.")) {
      try await api.server().customer("u").check(Feature<OnOff>(" "))
    }
    #expect(api.count == 0)
  }

  @Test func serverCallsAndAnswers() async throws {
    let api = FakeAPI { request in
      switch request.path {
      case "/keys/self":
        .json(
          #"{"id":"k","scopes":["usage:write","plans:read","plans:publish","tracks:assign"],"registration":true}"#
        )
      case "/customers/snapshot-keys":
        .json(
          #"{"keys":[{"kty":"EC","crv":"P-256","x":"a","y":"b","kid":"k1","alg":"ES256","use":"sig"}]}"#
        )
      case "/pricing/features":
        .json(
          #"{"environment":{"id":"e","name":"development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":3,"change":null,"features":[{"id":"f","key":"sso","name":"SSO","type":"boolean","description":"","unit":"","resetEvery":{"count":1,"unit":"months"},"archived":false,"includes":[]}]}"#
        )
      default:
        .json(
          #"{\#(Fixture.context),"customer":null,"defaultPlan":"free","products":[{"key":"app","name":"App","defaultPlan":"free"}],"plans":[{"id":"p","key":"pro","name":"Pro","description":"","kind":"plan","product":"app","salesLed":false,"status":"active","version":1,"default":false,"periods":[{"label":"monthly","count":1,"unit":"months"}],"attachesTo":[],"features":{"sso":true,"seats":5,"credits":"unlimited"},"listings":[{"period":"monthly","channels":[{"channel":{"provider":"stripe","connectionId":"c1"},"name":"Stripe","mode":"test","purchasable":true,"ids":{"price":"price_1"},"price":{"amount":1000,"currency":"aud","interval":"month","intervalCount":1,"tax":"exclusive"}}]}]}]}"#
        )
      }
    }
    let server = try api.server()
    try await api.run {
      let scopes = try await server.scopes()
      #expect(scopes.scopes == [.plansRead, .usageWrite, .tracksAssign])
      #expect(scopes.registration == true)
      #expect(scopes.contains(.usageWrite))
      let keys = try await server.snapshotKeys()
      #expect(keys.keys.first?.kid == "k1")
      #expect(api.last.header("Authorization") == nil)
      let features = try await server.features()
      #expect(features.features.first?.resetEvery?.unit == .months)
      let visitor = server.newVisitorID()
      let pricing = try await server.pricing(visitor: visitor)
      #expect(api.last.header("Entitler-Visitor") == visitor)
      let plan = try #require(pricing.plans.first)
      #expect(plan.features["credits"] == .unlimited)
      #expect(plan.features["seats"] == .amount(5))
      #expect(plan.listings.first?.channels.first?.price?.interval == .month)
      #expect(plan.listings.first?.channels.first?.channel.connectionID == "c1")
      #expect(!plan.isDefault)
      #expect(pricing.customer == nil)
    }
  }
}

@Suite struct ErrorTests {
  @Test func apiErrorsCarryEveryField() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"error":{"code":"payment_required","message":"Pay first.","payment":{"status":"requires_action","url":"https://pay.test"},"listingGaps":[{"kind":"unlisted","plan":"p","key":"pro","period":"monthly","channel":null}],"listingProblems":[{"channel":{"provider":"stripe","connectionId":"c"},"plan":"pro","period":"monthly","ids":{},"problem":"price_inactive"}],"extra":1}}"#,
        status: 402, headers: ["x-request-id": "req_1"])
    }
    do {
      _ = try await api.run {
        try await api.server().customer("u").subscribe(to: "pro", idempotencyKey: "key-1")
      }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.status == 402)
      #expect(error.code == .paymentRequired)
      #expect(error.message == "Pay first.")
      #expect(error.requestID == "req_1")
      #expect(error.idempotencyKey == "key-1")
      #expect(error.payment?.status == .requiresAction)
      #expect(error.listingGaps.first?.kind == .unlisted)
      #expect(error.listingProblems.first?.problem == .priceInactive)
      #expect(error.retryAfter == nil)
      #expect(error.description == "402 payment_required: Pay first.")
      #expect(EntitlerError.api(error).localizedDescription == "402 payment_required: Pay first.")
    }
  }

  @Test func errorsWithoutBodyUseHTTPError() async throws {
    let api = FakeAPI { _ in Reply(status: 418, body: Data("teapot".utf8)) }
    do {
      _ = try await api.run { try await api.server().customer("u").billing() }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.code == .httpError)
      #expect(error.message == "Entitler request failed with HTTP 418.")
      #expect(error.idempotencyKey == nil)
      #expect(error.listingGaps.isEmpty)
    }
  }

  @Test func unknownCodesAndBadBodiesStayReadable() async throws {
    let api = FakeAPI(replies: [.error(409, code: "brand_new_code"), .json("[]")])
    await #expect(throws: EntitlerError.self) {
      try await api.run { try await api.server().customer("u").billing() }
    }
    do {
      _ = try await api.run { try await api.server().customer("u").providers() }
    } catch EntitlerError.api(let error) {
      #expect(error.status == 200)
      #expect(error.code == .httpError)
    }
    #expect(ErrorCode(rawValue: "brand_new_code").description == "brand_new_code")
  }

  @Test func connectionAndTimeoutErrorsDescribeThemselves() {
    let connection = ConnectionError(
      underlyingError: URLError(.cannotConnectToHost), idempotencyKey: "k")
    #expect(connection.description.hasPrefix("Entitler could not be reached"))
    #expect(EntitlerError.connection(connection).errorDescription == connection.message)
    let timeout = TimeoutError(timeout: 5, idempotencyKey: nil)
    #expect(timeout.description == "Entitler did not answer within 5 seconds.")
    #expect(EntitlerError.timeout(timeout).description == timeout.message)
    let token = TokenError(message: "No token.", underlyingError: nil)
    #expect(EntitlerError.token(token).description == "No token.")
    #expect(token.errorDescription == "No token.")
    let snapshot = SnapshotError(code: .expired, message: "Old.")
    #expect(EntitlerError.snapshot(snapshot).description == "Old.")
    #expect(snapshot.code.rawValue == "snapshot_expired")
    #expect(snapshot.errorDescription == "Old.")
    #expect(ArgumentError(message: "m").errorDescription == "m")
    #expect(ArgumentError(message: "m").description == "m")
  }
}
