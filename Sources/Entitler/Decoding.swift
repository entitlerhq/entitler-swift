import Foundation

struct AnswerMismatch: Error, CustomStringConvertible {
  let path: [String]

  var description: String {
    "The answer lacks a required field, or holds one of another type, at \(path.joined(separator: "."))."
  }
}

func at<Value>(_ step: String, _ decode: () throws -> Value) throws -> Value {
  do {
    return try decode()
  } catch let mismatch as AnswerMismatch {
    throw AnswerMismatch(path: [step] + mismatch.path)
  }
}

func given<Value>(_ value: Value?) throws -> Value {
  guard let value else { throw AnswerMismatch(path: []) }
  return value
}

func date(_ seconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

func wire<Answer: Decodable>(_ type: Answer.Type, _ body: Data) throws -> Answer {
  try JSONDecoder().decode(type, from: body)
}

private let featureTypes: [String: FeatureType] = [
  "ENTITLED_FEATURE_KIND_SWITCH": .switch,
  "ENTITLED_FEATURE_KIND_CONFIGURATION": .configuration,
  "ENTITLED_FEATURE_KIND_METERED": .metered,
  "ENTITLED_FEATURE_KIND_GROUP": .group,
]

private func openName(_ value: String?, prefix: String) throws -> OpenName {
  let name = try given(value)
  guard name.hasPrefix(prefix) else { return OpenName(rawValue: name) }
  return OpenName(rawValue: String(name.dropFirst(prefix.count)).lowercased())
}

private func limit(_ value: Wire.Limit) throws -> Limit {
  value.unlimited != nil ? .unlimited : .amount(value.count ?? 0)
}

private func featureValue(_ value: Wire.FeatureValue?, entitled: Bool) throws -> FeatureValue {
  guard let value else { return .amount(0) }
  if let on = value.switch { return on ? .on : .amount(0) }
  if let metered = value.metered { return try at("metered") { try amount(limit(metered)) } }
  if let setting = value.configuration {
    return try at("configuration") { try amount(limit(setting)) }
  }
  if value.group != nil { return entitled ? .on : .amount(0) }
  return .amount(0)
}

private func amount(_ limit: Limit) -> FeatureValue {
  switch limit {
  case .amount(let count): .amount(count)
  case .unlimited: .unlimited
  }
}

private func sourceValue(_ value: Wire.FeatureValue?) throws -> FeatureValue? {
  try value.map { try featureValue($0, entitled: true) }
}

private func through(_ key: String?) -> String? {
  key.flatMap { $0.isEmpty ? nil : $0 }
}

private func source(_ value: Wire.EntitlementSource) throws -> EntitlementSource? {
  if let plan = value.plan {
    return try at("plan") {
      .plan(
        PlanSource(
          planID: try at("planId") { try given(plan.planId) },
          plan: try at("planKey") { try given(plan.planKey) },
          name: try at("planName") { try given(plan.planName) },
          product: plan.productId,
          version: try at("versionNumber") { try given(plan.versionNumber) },
          byDefault: false,
          value: try at("value") { try sourceValue(plan.value) },
          through: through(plan.throughFeatureKey)))
    }
  }
  if let plan = value.defaultPlan {
    return try at("defaultPlan") {
      .plan(
        PlanSource(
          planID: try at("planId") { try given(plan.planId) },
          plan: try at("planKey") { try given(plan.planKey) },
          name: try at("planName") { try given(plan.planName) },
          product: plan.productId,
          version: try at("versionNumber") { try given(plan.versionNumber) },
          byDefault: true,
          value: nil,
          through: through(plan.throughFeatureKey)))
    }
  }
  if let addOn = value.addOn {
    return try at("addOn") {
      .addOn(
        AddOnSource(
          planID: try at("planId") { try given(addOn.planId) },
          plan: try at("planKey") { try given(addOn.planKey) },
          name: try at("planName") { try given(addOn.planName) },
          version: try at("versionNumber") { try given(addOn.versionNumber) },
          quantity: try at("quantity") { try given(addOn.quantity) },
          value: try at("value") { try sourceValue(addOn.value) },
          through: through(addOn.throughFeatureKey)))
    }
  }
  if let grant = value.grant {
    return try at("grant") {
      .grant(
        GrantSource(
          grant: try at("grantId") { try given(grant.grantId) },
          until: grant.until.map(date),
          value: try at("value") { try sourceValue(grant.value) },
          through: through(grant.throughFeatureKey)))
    }
  }
  if let group = value.group {
    return .group(features: group.featureKeys ?? [])
  }
  return nil
}

private func upgrade(_ value: Wire.Upgrade) throws -> Upgrade {
  Upgrade(
    kind: try at("kind") { try openName(value.kind, prefix: "UPGRADE_KIND_") },
    planID: try at("planId") { try given(value.planId) },
    plan: try at("planKey") { try given(value.planKey) },
    name: try at("planName") { try given(value.planName) },
    product: value.productId,
    move: try at("move") { try openName(value.move, prefix: "UPGRADE_MOVE_") },
    action: try at("action") { try openName(value.action, prefix: "UPGRADE_ACTION_") })
}

private func meter(_ value: Wire.Meter) throws -> Meter {
  Meter(
    used: value.used ?? 0,
    held: value.held ?? 0,
    banked: value.banked ?? 0,
    remaining: try at("remaining") { try limit(value.remaining ?? Wire.Limit(count: 0)) },
    resetsAt: value.resetsAt.map(date))
}

private func entitlement(_ value: Wire.Entitlement) throws -> Entitlement {
  let entitled = value.entitled ?? false
  let kind = try at("kind") { try given(value.kind) }
  return Entitlement(
    key: try at("featureKey") { try given(value.featureKey) },
    type: featureTypes[kind] ?? FeatureType(rawValue: kind),
    entitled: entitled,
    value: try at("value") { try featureValue(value.value, entitled: entitled) },
    sources: try at("sources") {
      try (value.sources ?? []).enumerated().compactMap { index, item in
        try at(String(index)) { try source(item) }
      }
    },
    upgrades: try at("upgrades") {
      try (value.upgrades ?? []).enumerated().map { index, item in
        try at(String(index)) { try upgrade(item) }
      }
    },
    meter: try at("meter") { try value.meter.map(meter) })
}

private func served(_ value: Wire.ServedCatalogue?) throws -> Served {
  let track = try value?.track.map { track in
    ServedTrack(
      id: try at("id") { try given(track.id) }, name: try at("name") { try given(track.name) })
  }
  let source: ServedSource
  if let release = value?.release {
    source = .release(
      id: try at("release") { try at("id") { try given(release.id) } },
      number: try at("release") { try at("number") { try given(release.number) } })
  } else if let change = value?.changeId {
    source = .change(id: change)
  } else {
    source = .nothing
  }
  return Served(track: track, source: source)
}

private func context(
  customer: Wire.EntitledCustomer?, asOf: Int64?, nextChangeAt: Int64?,
  served value: Wire.ServedCatalogue?
) throws -> AnswerContext {
  AnswerContext(
    customer: try at("customer") { try at("externalId") { try given(customer?.externalId) } },
    customerID: customer?.customerId,
    asOf: date(try at("asOf") { try given(asOf) }),
    nextChangeAt: nextChangeAt.map(date),
    served: try at("served") { try served(value) })
}

func decodeCheck(_ body: Data) throws -> Check {
  let answer = try wire(Wire.CheckFeatureResponse.self, body)
  return Check(
    entitlement: try at("entitlement") { try entitlement(given(answer.entitlement)) },
    context: try context(
      customer: answer.customer, asOf: answer.asOf, nextChangeAt: answer.nextChangeAt,
      served: answer.served))
}

func decodeEntitlements(_ body: Data) throws -> Entitlements {
  let answer = try wire(Wire.ListEntitlementsResponse.self, body)
  return Entitlements(
    entitlements: try at("entitlements") {
      try (answer.entitlements ?? []).enumerated().map { index, item in
        try at(String(index)) { try entitlement(item) }
      }
    },
    context: try context(
      customer: answer.customer, asOf: answer.asOf, nextChangeAt: answer.nextChangeAt,
      served: answer.served))
}
