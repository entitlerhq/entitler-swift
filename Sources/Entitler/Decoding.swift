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

private func openName(_ name: String, prefix: String) -> OpenName {
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
          planID: plan.planId,
          plan: plan.planKey,
          name: plan.planName,
          product: plan.productId,
          version: plan.versionNumber,
          byDefault: false,
          value: try at("value") { try sourceValue(plan.value) },
          through: through(plan.throughFeatureKey)))
    }
  }
  if let plan = value.defaultPlan {
    return try at("defaultPlan") {
      .plan(
        PlanSource(
          planID: plan.planId,
          plan: plan.planKey,
          name: plan.planName,
          product: plan.productId,
          version: plan.versionNumber,
          byDefault: true,
          value: nil,
          through: through(plan.throughFeatureKey)))
    }
  }
  if let addOn = value.addOn {
    return try at("addOn") {
      .addOn(
        AddOnSource(
          planID: addOn.planId,
          plan: addOn.planKey,
          name: addOn.planName,
          version: addOn.versionNumber,
          quantity: addOn.quantity,
          value: try at("value") { try sourceValue(addOn.value) },
          through: through(addOn.throughFeatureKey)))
    }
  }
  if let grant = value.grant {
    return try at("grant") {
      .grant(
        GrantSource(
          grant: grant.grantId,
          until: grant.until.map(date),
          value: try at("value") { try sourceValue(grant.value) },
          through: through(grant.throughFeatureKey)))
    }
  }
  if let group = value.group {
    return .group(features: group.featureKeys)
  }
  return nil
}

private func upgrade(_ value: Wire.Upgrade) throws -> Upgrade {
  Upgrade(
    kind: openName(value.kind, prefix: "UPGRADE_KIND_"),
    planID: value.planId,
    plan: value.planKey,
    name: value.planName,
    product: value.productId,
    move: openName(value.move, prefix: "UPGRADE_MOVE_"),
    action: openName(value.action, prefix: "UPGRADE_ACTION_"))
}

private func meter(_ value: Wire.Meter) throws -> Meter {
  Meter(
    used: value.used,
    held: value.held,
    banked: value.banked,
    remaining: try at("remaining") { try limit(value.remaining ?? Wire.Limit(count: 0)) },
    resetsAt: value.resetsAt.map(date))
}

private func entitlement(_ value: Wire.Entitlement) throws -> Entitlement {
  Entitlement(
    key: value.featureKey,
    type: featureTypes[value.kind] ?? FeatureType(rawValue: value.kind),
    entitled: value.entitled,
    value: try at("value") { try featureValue(value.value, entitled: value.entitled) },
    sources: try at("sources") {
      try value.sources.enumerated().compactMap { index, item in
        try at(String(index)) { try source(item) }
      }
    },
    upgrades: try at("upgrades") {
      try value.upgrades.enumerated().map { index, item in
        try at(String(index)) { try upgrade(item) }
      }
    },
    meter: try at("meter") { try value.meter.map(meter) })
}

private func served(_ value: Wire.ServedCatalogue?) throws -> Served {
  let track = value?.track.map { ServedTrack(id: $0.id, name: $0.name) }
  let source: ServedSource
  if let release = value?.release {
    source = .release(
      id: try at("release") { release.id },
      number: try at("release") { release.number })
  } else if let change = value?.changeId {
    source = .change(id: change)
  } else {
    source = .nothing
  }
  return Served(track: track, source: source)
}

private func context(
  customer: Wire.EntitledCustomer?, asOf: Int64, nextChangeAt: Int64?,
  served value: Wire.ServedCatalogue?
) throws -> AnswerContext {
  AnswerContext(
    customer: try at("customer") { try given(customer).externalId },
    customerID: customer?.customerId,
    asOf: date(asOf),
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
      try answer.entitlements.enumerated().map { index, item in
        try at(String(index)) { try entitlement(item) }
      }
    },
    context: try context(
      customer: answer.customer, asOf: answer.asOf, nextChangeAt: answer.nextChangeAt,
      served: answer.served))
}
