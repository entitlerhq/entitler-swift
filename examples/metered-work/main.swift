import Entitler
import Foundation

enum Features {
  static let aiCredits = Feature<Metered>("ai_credits")
}

func summarise(_ text: String) async throws -> (summary: String, credits: Int64) {
  (String(text.prefix(20)), Int64(text.count / 10 + 1))
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("metered-\(UUID().uuidString.prefix(8).lowercased())")
try await customer.register(name: "Katherine Johnson")

do {
  let document = "Orbital mechanics for the Friendship 7 flight."
  var summary = ""
  do {
    let used = try await customer.withHold(of: Features.aiCredits, amount: 10) { _ in
      let answer = try await summarise(document)
      summary = answer.summary
      return answer.credits
    }
    print("Summary: \(summary) (\(used) credits)")
  } catch EntitlerError.usageRefused(let answer) {
    print("Not enough credits: \(answer.refusal?.rawValue ?? "refused")")
  }

  let streamed = try await customer.recordUsage(
    of: Features.aiCredits, amount: 3, mode: .observe, idempotencyKey: "stream-\(UUID().uuidString)"
  )
  print("Streamed tokens recorded, \(streamed.overBy) past the allowance")
} catch {
  _ = try? await customer.delete(erase: true)
  throw error
}
try await customer.delete(erase: true)
