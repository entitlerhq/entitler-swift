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

private func shortName(_ name: String, prefix: String) -> String {
  guard name.hasPrefix(prefix) else { return name }
  return String(name.dropFirst(prefix.count)).lowercased()
}

private func openName(_ name: String, prefix: String) -> OpenName {
  OpenName(rawValue: shortName(name, prefix: prefix))
}

private func limit(_ value: Wire.Limit) -> Limit {
  value.unlimited != nil ? .unlimited : .amount(value.count ?? 0)
}

private func featureValue(_ value: Wire.FeatureValue?, entitled: Bool) throws -> FeatureValue {
  guard let value else { return .amount(0) }
  if let on = value.switch { return on ? .on : .amount(0) }
  if let metered = value.metered { return amount(limit(metered)) }
  if let setting = value.configuration {
    return amount(limit(setting))
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

private func upgrade(_ value: Wire.Upgrade) -> Upgrade {
  Upgrade(
    kind: openName(value.kind, prefix: "UPGRADE_KIND_"),
    planID: value.planId,
    plan: value.planKey,
    name: value.planName,
    product: value.productId,
    move: openName(value.move, prefix: "UPGRADE_MOVE_"),
    action: openName(value.action, prefix: "UPGRADE_ACTION_"))
}

private func meter(_ value: Wire.Meter) -> Meter {
  Meter(
    used: value.used,
    held: value.held,
    banked: value.banked,
    remaining: limit(value.remaining ?? Wire.Limit(count: 0)),
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
    upgrades: value.upgrades.map(upgrade),
    meter: value.meter.map(meter))
}

private func served(_ value: Wire.ServedCatalogue?) throws -> Served {
  let track = value?.track.map { ServedTrack(id: $0.id, name: $0.name) }
  let source: ServedSource
  if let release = value?.release {
    source = .release(id: release.id, number: release.number)
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

func decodeUsage(_ body: Data) throws -> UsageResult {
  let answer = try wire(Wire.ReportUsageResponse.self, body)
  return try at("tracked") {
    let tracked = try given(answer.tracked)
    let usage = try at("usage") { try given(tracked.usage) }
    return UsageResult(
      entitlement: try at("entitlement") { try entitlement(given(tracked.entitlement)) },
      context: try context(
        customer: tracked.customer, asOf: tracked.asOf, nextChangeAt: nil, served: tracked.served),
      outcome: UsageOutcome(rawValue: shortName(usage.outcome, prefix: "USAGE_OUTCOME_")),
      refusal: usage.refusal.map {
        UsageRefusal(rawValue: shortName($0, prefix: "USAGE_REFUSAL_"))
      },
      id: usage.usageId,
      holdID: usage.holdId,
      mode: UsageMode(rawValue: shortName(usage.mode, prefix: "USAGE_MODE_")),
      amount: usage.amount,
      meterChange: usage.meterChange,
      overBy: usage.overBy,
      late: usage.late,
      occurredAt: usage.occurredAtMs.map(milliseconds),
      expiresAt: usage.expiresAtMs.map(milliseconds),
      replayed: usage.replayed)
  }
}

private func milliseconds(_ value: Int64) -> Date {
  Date(timeIntervalSince1970: TimeInterval(value) / 1000)
}

private func customerRecord(_ value: Wire.Customer) -> CustomerRecord {
  CustomerRecord(
    customer: value.externalId,
    customerID: value.id,
    name: value.name,
    email: value.email,
    attributes: Dictionary(value.attributes.map { ($0.key, $0.value) }) { $1 },
    trackID: value.trackId,
    money: openName(value.money, prefix: "CUSTOMER_MONEY_"),
    revision: value.revision,
    createdAt: date(value.createdAt),
    updatedAt: date(value.updatedAt))
}

func decodeCustomer(_ body: Data) throws -> CustomerRecord {
  let answer = try wire(Wire.GetCustomerResponse.self, body)
  return try at("customer") { customerRecord(try given(answer.customer)) }
}

func decodeRegistered(_ body: Data) throws -> RegisteredCustomer {
  let answer = try wire(Wire.RegisterCustomerResponse.self, body)
  return RegisteredCustomer(
    record: try at("customer") { customerRecord(try given(answer.customer)) },
    created: answer.created)
}

func decodeToken(_ body: Data) throws -> CustomerToken {
  let answer = try wire(Wire.CreateTokenResponse.self, body)
  return CustomerToken(
    token: answer.token,
    id: answer.tokenId,
    customerID: answer.customerId,
    scopes: answer.scopes.map { scope in
      var name = shortName(scope, prefix: "CUSTOMER_TOKEN_SCOPE_")
      if let split = name.lastIndex(of: "_") { name.replaceSubrange(split...split, with: ":") }
      return CustomerTokenScope(rawValue: name)
    },
    expiresAt: date(answer.expiresAt))
}
