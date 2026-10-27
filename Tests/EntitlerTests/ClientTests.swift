import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class Tokens: Sendable {
  private let queue: LockedValue<[Result<String, TokenFailure>]>
  private let asked = LockedValue(0)

  struct TokenFailure: Error {}

  init(_ answers: [Result<String, TokenFailure>]) {
    queue = LockedValue(answers)
  }

  var calls: Int { asked.read() }

  var provider: TokenProvider {
    { [self] in
      asked.update { $0 += 1 }
      return try queue.update { $0.isEmpty ? .failure(TokenFailure()) : $0.removeFirst() }.get()
    }
  }
}

func client(_ api: FakeAPI, _ tokens: Tokens, key: String? = nil) throws -> EntitlerClient {
  try EntitlerClient(
    kind: key == nil ? .token : .identity, cache: MemoryCacheStore(capacity: 10),
    options: EntitlerOptions(maxRetries: 0), exchange: api.exchange, hooks: instantHooks,
    credentials: provided(tokens.provider, key: key))
}

let revalidated = ["ETag": "W/\"v1\"", "Cache-Control": "private, no-cache"]

@Suite struct ClientTests {
  @Test func meChecksWithTheProvidersToken() async throws {
    let api = FakeAPI([Answer(body: switchCheck)])
    let tokens = Tokens([.success("ctk_1")])
    let check = try await client(api, tokens).me.check("priority_support")

    #expect(check.entitled)
    let request = try #require(api.requests.first)
    #expect(request.url?.path == "/v1/customers/me/entitlements/priority_support")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ctk_1")
  }

  @Test func aRefusedTokenIsReplacedOnceAndNeverSentAgain() async throws {
    let api = FakeAPI([
      Answer(status: 401, body: refusal("Unauthenticated", "KEY_INACTIVE")),
      Answer(headers: ["Cache-Control": "private, max-age=60"], body: switchCheck),
    ])
    let tokens = Tokens([.success("ctk_old"), .success("ctk_new")])
    let entitler = try client(api, tokens)
    _ = try await entitler.me.check("priority_support")
    _ = try await entitler.me.check("priority_support")

    let sent = api.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    #expect(sent == ["Bearer ctk_old", "Bearer ctk_new"])
    #expect(tokens.calls == 2)
  }

  @Test func aSecondRefusalFails() async throws {
    let api = FakeAPI([
      Answer(status: 401, body: refusal("Unauthenticated", "KEY_INACTIVE")),
      Answer(status: 401, body: refusal("Unauthenticated", "KEY_INACTIVE")),
    ])
    let entitler = try client(api, Tokens([.success("ctk_1"), .success("ctk_2")]))
    await #expect(throws: EntitlerError.self) { try await entitler.me.check("priority_support") }
    #expect(api.requests.count == 2)
  }

  @Test func aProviderAnsweringARefusedTokenFailsWithoutSendingIt() async throws {
    let api = FakeAPI([Answer(status: 401, body: refusal("Unauthenticated", "KEY_INACTIVE"))])
    let entitler = try client(api, Tokens([.success("ctk_1"), .success("ctk_1")]))
    do {
      _ = try await entitler.me.check("priority_support")
      Issue.record("Expected a token error.")
    } catch EntitlerError.token(let error) {
      #expect(error.message == Messages.tokenRefused)
    }
    #expect(api.requests.count == 1)
  }

  @Test func aKeptAnswerStandsInWhenTheProviderFailsAfterARefusal() async throws {
    let api = FakeAPI([
      Answer(headers: revalidated, body: switchCheck),
      Answer(status: 401, body: refusal("Unauthenticated", "KEY_INACTIVE")),
    ])
    let reported = LockedValue(0)
    let entitler = try EntitlerClient(
      kind: .token, cache: MemoryCacheStore(capacity: 10),
      options: EntitlerOptions(maxRetries: 0, onError: { _ in reported.update { $0 += 1 } }),
      exchange: api.exchange, hooks: instantHooks,
      credentials: provided(Tokens([.success("ctk_1")]).provider, key: nil))
    _ = try await entitler.me.check("priority_support")
    let afterRefusal = try await entitler.me.check("priority_support")
    let withoutToken = try await entitler.me.check("priority_support")

    #expect(afterRefusal.stale)
    #expect(withoutToken.stale)
    #expect(api.requests.count == 2)
    #expect(reported.read() == 2)
  }

  @Test func isEntitledAnswersItsDefaultWhenTheProviderFails() async throws {
    let api = FakeAPI([])
    let entitler = try client(api, Tokens([]))
    #expect(await entitler.me.isEntitled(to: "priority_support", default: true))
    #expect(api.requests.isEmpty)
  }

  @Test func anIdentityClientSendsTheKeyAndTheIdentityTokenAndRegisters() async throws {
    let api = FakeAPI([Answer(body: #"{"created": false, "customer": \#(customerRecordJSON)}"#)])
    let entitler = try client(api, Tokens([.success("idt_1")]), key: "pk_test_1")
    let registered = try await entitler.register()

    let request = try #require(api.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/v1/customers/me")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pk_test_1")
    #expect(request.value(forHTTPHeaderField: "Entitler-Identity-Token") == "idt_1")
    #expect(!registered.created)
    #expect(entitler.kind == .identity)
  }

  @Test func theClientNeverShowsItsCredential() throws {
    let entitler = try EntitlerClient(token: "ctk_secret")
    #expect(!"\(entitler)".contains("ctk_secret"))
    #expect(!String(reflecting: entitler).contains("ctk_secret"))
    #expect(throws: ArgumentError.self) { try EntitlerClient(token: " ") }
  }
}
