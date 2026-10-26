import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct Answer: Sendable {
  var status = 200
  var headers: [String: String] = [:]
  var body = "{}"
  var failure: URLError.Code?
}

final class FakeAPI: Sendable {
  private let answers: LockedValue<[Answer]>
  private let received = LockedValue<[URLRequest]>([])

  init(_ answers: [Answer]) {
    self.answers = LockedValue(answers)
  }

  var requests: [URLRequest] { received.read() }

  var exchange: Exchange {
    { [self] request in
      received.update { $0.append(request) }
      let answer = answers.update { queue in
        queue.isEmpty ? Answer(status: 599) : queue.removeFirst()
      }
      if let failure = answer.failure { throw URLError(failure) }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
        headerFields: answer.headers)!
      return (Data(answer.body.utf8), response)
    }
  }

  func server(
    cache: (any CacheStore)? = MemoryCacheStore(capacity: 10),
    options: EntitlerOptions = EntitlerOptions(), hooks: Hooks = instantHooks
  ) throws -> EntitlerServer {
    try EntitlerServer(
      key: "test-secret-key", cache: cache, options: options, exchange: exchange, hooks: hooks)
  }
}

let instantHooks = Hooks(sleep: { _ in }, random: { $0.lowerBound })

func refusal(_ code: String, _ reason: String?, parameters: [String: String] = [:]) -> String {
  let reasonJSON = reason.map { "\"\($0)\"" } ?? "null"
  let parametersJSON = parameters.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
  return #"{"error":{"code":"\#(code)","reason":\#(reasonJSON),"parameters":{\#(parametersJSON)}}}"#
}

let switchCheck = #"""
  {
    "asOf": 1790000000,
    "customer": {"customerId": "cu_1", "externalId": "ada"},
    "served": {"track": {"id": "tr_1", "name": "All customers"}, "release": {"id": "re_1", "number": 12}},
    "entitlement": {
      "featureKey": "priority_support",
      "kind": "ENTITLED_FEATURE_KIND_SWITCH",
      "entitled": true,
      "value": {"switch": true},
      "sources": [
        {"plan": {"planId": "pl_1", "planKey": "pro", "planName": "Pro", "productId": "pr_1",
          "versionNumber": 3, "value": {"switch": true}, "throughFeatureKey": ""}},
        {"grant": {"grantId": "gr_1", "until": 1790086400}}
      ],
      "upgrades": [
        {"kind": "UPGRADE_KIND_PLAN", "planId": "pl_2", "planKey": "team", "planName": "Team",
          "move": "UPGRADE_MOVE_UPGRADE", "action": "UPGRADE_ACTION_BUY"}
      ]
    }
  }
  """#

let meteredCheck = #"""
  {
    "asOf": 1790000000,
    "nextChangeAt": 1790500000,
    "customer": {"externalId": "ada"},
    "served": {"nothing": {}},
    "entitlement": {
      "featureKey": "ai_credits",
      "kind": "ENTITLED_FEATURE_KIND_METERED",
      "entitled": true,
      "value": {"metered": {"count": 1000}},
      "meter": {"used": 250, "held": 50, "banked": 0, "remaining": {"count": 700}, "resetsAt": 1790500000}
    }
  }
  """#

let entitlementList = #"""
  {
    "asOf": 1790000000,
    "customer": {"externalId": "ada"},
    "served": {"changeId": "ch_1"},
    "entitlements": [
      {"featureKey": "priority_support", "kind": "ENTITLED_FEATURE_KIND_SWITCH", "entitled": true,
        "value": {"switch": true}},
      {"featureKey": "seats", "kind": "ENTITLED_FEATURE_KIND_CONFIGURATION", "entitled": true,
        "value": {"configuration": {"unlimited": {}}}},
      {"featureKey": "collaboration", "kind": "ENTITLED_FEATURE_KIND_GROUP", "entitled": false,
        "value": {"group": {"members": []}}, "sources": [{"group": {"featureKeys": ["seats"]}}]}
    ]
  }
  """#
