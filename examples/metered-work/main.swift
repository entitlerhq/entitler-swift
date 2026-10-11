import Entitler
import Foundation

enum Features {
  static let aiCredits = Feature<Metered>("ai_credits")
}

func summarise(_ text: String) async throws -> (summary: String, credits: Int64) {
  (String(text.prefix(20)), Int64(text.count / 10 + 1))
}

func streamTokens() -> AsyncStream<Int64> {
  AsyncStream { continuation in
    for total in [1, 2, 3, 4] { continuation.yield(Int64(total)) }
    continuation.finish()
  }
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("metered-\(UUID().uuidString.prefix(8).lowercased())")
try await customer.register(name: "Katherine Johnson")

do {
  do {
    let hold = try await customer.startHold(
      of: Features.aiCredits, amount: 8, idempotencyKey: "message-\(UUID().uuidString)")
    try await hold.run { hold in
      try hold.use(0)
      for await total in streamTokens() {
        try hold.use(total)
      }
    }
    print("Streamed reply charged for the tokens it used")
  } catch EntitlerError.usageRefused(let answer) {
    print("Not enough credits: \(answer.refusal?.rawValue ?? "refused")")
  }

  let document = "Orbital mechanics for the Friendship 7 flight."
  do {
    let summary = try await customer.withHold(
      of: Features.aiCredits, amount: 10, idempotencyKey: "summary-\(UUID().uuidString)"
    ) { hold in
      let answer = try await summarise(document)
      try hold.use(answer.credits)
      return answer.summary
    }
    print("Summary: \(summary)")
  } catch EntitlerError.usageRefused(let answer) {
    print("Not enough credits: \(answer.refusal?.rawValue ?? "refused")")
  }

  let observed = try await customer.recordUsage(
    of: Features.aiCredits, amount: 3, idempotencyKey: "bandwidth-\(UUID().uuidString)",
    mode: .observe)
  print("Work already done recorded, \(observed.overBy) past the allowance")
} catch {
  try? await customer.erase()
  throw error
}
try await customer.erase()
