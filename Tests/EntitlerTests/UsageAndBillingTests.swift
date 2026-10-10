import Foundation
import Testing

@testable import Entitler

@Suite struct UsageTests {
  static let credits = Feature<Metered>("ai_credits")

  @Test func recordUsageSendsTheCallersKeyAndOnlyGivenFields() async throws {
    let api = FakeAPI { request in
      .json(
        Fixture.usage(), status: 201,
        headers: request.header("Idempotency-Key") == "job-2"
          ? ["Idempotent-Replayed": "true"] : [:])
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let result = try await customer.recordUsage(
        of: Self.credits, amount: 3, idempotencyKey: "job-1")
      #expect(result.outcome == .recorded)
      #expect(result.reportedAs == .api)
      #expect(result.mode == .gate)
      #expect(!result.replayed)
      #expect(api.last.method == "POST")
      #expect(api.last.path == "/customers/u/usage")
      #expect(api.last.header("Content-Type") == "application/json")
      #expect(api.last.header("Idempotency-Key") == "job-1")
      #expect(api.last.json?.keys.sorted() == ["amount", "feature"])
      let replayed = try await customer.recordUsage(
        of: Self.credits, amount: 2, idempotencyKey: "job-2", mode: .observe,
        occurredAt: Date(timeIntervalSince1970: 1_782_898_200), register: true)
      #expect(replayed.replayed)
      let json = try #require(api.last.json)
      #expect(json["mode"] as? String == "observe")
      #expect(json["occurredAt"] as? String == "2026-07-01T09:30:00.000Z")
      #expect(json["register"] as? Bool == true)
    }
  }

  @Test func usageKeysAreCheckedBeforeAnyRequest() async throws {
    let api = FakeAPI()
    let customer = try api.server().customer("u")
    let general = ArgumentError(
      message: "Pass idempotencyKey as 1 to 200 printable ASCII characters.")
    await #expect(throws: general) {
      try await customer.recordUsage(of: Self.credits, amount: 1, idempotencyKey: "")
    }
    await #expect(throws: general) {
      try await customer.holdUsage(of: Self.credits, amount: 1, idempotencyKey: " job")
    }
    await #expect(throws: general) {
      try await api.server().customer("u").adjustMeter(Self.credits, by: 1, idempotencyKey: "é")
    }
    await #expect(
      throws: ArgumentError(message: "Pass idempotencyKey as 1 to 193 printable ASCII characters.")
    ) {
      try await customer.startHold(
        of: Self.credits, amount: 1, idempotencyKey: String(repeating: "k", count: 194))
    }
    #expect(api.count == 0)
  }

  @Test(arguments: [
    "recorded", "duplicate", "refused", "held", "settled", "released", "cancelled", "adjusted",
    "brand_new",
  ])
  func everyOutcomeDecodes(outcome: String) async throws {
    let api = FakeAPI { _ in
      .json(
        Fixture.usage(
          outcome: outcome, refusal: outcome == "refused" ? #""over_allowance""# : "null"))
    }
    let result = try await api.run {
      try await api.server().customer("u").recordUsage(
        of: Self.credits, amount: 1, idempotencyKey: "k")
    }
    #expect(result.outcome.rawValue == outcome)
    #expect(result.outcome == UsageOutcome(rawValue: outcome))
    if outcome == "refused" { #expect(result.refusal == .overAllowance) }
    if outcome == "brand_new" { #expect(result.outcome == .unknown("brand_new")) }
  }

  @Test func holdsSettleReleaseAndReadBack() async throws {
    let api = FakeAPI { request in
      request.method == "GET"
        ? .json(
          #"{"id":"h_1","customer":"u","feature":"ai_credits","amount":10,"state":"open","expiresAt":"2026-10-09T01:52:13Z","settledAmount":null,"usageId":null,"createdAt":"2026-10-09T01:47:13Z"}"#
        )
        : .json(Fixture.usage(outcome: "held", holdID: #""h_1""#))
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let held = try await customer.holdUsage(
        of: Self.credits, amount: 10, idempotencyKey: "job", ttlSeconds: 60)
      #expect(held.holdID == "h_1")
      #expect(api.last.path == "/customers/u/usage/holds")
      #expect(api.last.json?["ttlSeconds"] as? Int == 60)
      #expect(api.last.header("Idempotency-Key") == "job")
      try await customer.settleUsage(hold: "h_1", amount: 4)
      #expect(api.last.path == "/customers/u/usage/holds/h_1/settle")
      #expect(api.last.json?["amount"] as? Int == 4)
      try await customer.releaseUsage(hold: "h_1")
      #expect(api.last.method == "DELETE")
      #expect(api.last.path == "/customers/u/usage/holds/h_1")
      let hold = try await customer.hold(id: "h_1")
      #expect(hold.state == .open)
      #expect(hold.usageID == nil)
      await #expect(throws: ArgumentError(message: "Provide the id of the hold.")) {
        try await customer.releaseUsage(hold: "")
      }
    }
  }

  static func holdAPI(
    settle: Reply? = nil, release: Reply? = nil, record: Reply? = nil, outcome: String = "held"
  ) -> FakeAPI {
    FakeAPI { request in
      if request.path.hasSuffix("/settle"), let settle { return settle }
      if request.method == "DELETE", let release { return release }
      if request.path.hasSuffix("/usage"), let record { return record }
      return .json(
        Fixture.usage(
          outcome: request.path.hasSuffix("/settle")
            ? "settled" : request.method == "DELETE" ? "released" : outcome,
          holdID: #""h_1""#, amount: 10, expiresAt: #""2026-10-09T01:52:13.000Z""#))
    }
  }

  @Test func startHoldAnswersAHandleBeforeAnyWork() async throws {
    let api = Self.holdAPI()
    let hold = try await api.run {
      try await api.server().customer("u").startHold(
        of: Self.credits, amount: 10, idempotencyKey: "message-1", ttlSeconds: 120)
    }
    #expect(hold.id == "h_1")
    #expect(hold.amount == 10)
    #expect(hold.expiresAt == parseInstant("2026-10-09T01:52:13.000Z"))
    #expect(!hold.isDuplicate)
    #expect(hold.result.outcome == .held)
    #expect(api.count == 1)
    #expect(api.last.header("Idempotency-Key") == "message-1")
    #expect(api.last.json?["ttlSeconds"] as? Int == 120)
    let duplicate = try await api.run {
      try await Self.holdAPI(outcome: "duplicate").server().customer("u").startHold(
        of: Self.credits, amount: 10, idempotencyKey: "message-1")
    }
    #expect(duplicate.isDuplicate)
  }

  @Test func startHoldRefusesAndReplays() async throws {
    for outcome in ["refused", "settled", "released", "brand_new"] {
      let api = FakeAPI { _ in
        .json(
          Fixture.usage(
            outcome: outcome, refusal: outcome == "refused" ? #""not_entitled""# : "null",
            holdID: #""h_1""#))
      }
      let ran = Box(false)
      do {
        _ = try await api.run {
          try await api.server().customer("u").withHold(
            of: Self.credits, amount: 10, idempotencyKey: "job"
          ) { _ in
            ran.with { $0 = true }
          }
        }
        Issue.record("Expected an error for \(outcome)")
      } catch EntitlerError.usageRefused(let answer) {
        #expect(outcome == "refused")
        #expect(answer.refusal == .notEntitled)
        #expect(EntitlerError.usageRefused(answer).description.contains("not_entitled"))
      } catch EntitlerError.usageReplayed(let answer) {
        #expect(outcome != "refused")
        #expect(answer.outcome.rawValue == outcome)
        #expect(EntitlerError.usageReplayed(answer).description.contains("already"))
      }
      #expect(!ran.get)
    }
  }

  @Test func finishSettlesTheReportedAmountOrTheHeldAmount() async throws {
    for (reported, settled) in [(Int64?(7), 7), (nil, 10), (0, 0)] {
      let api = Self.holdAPI()
      try await api.run {
        let hold = try await api.server().customer("u").startHold(
          of: Self.credits, amount: 10, idempotencyKey: "job")
        if let reported { try hold.use(reported) }
        let result = try await hold.finish()
        #expect(result.outcome == .settled)
      }
      #expect(api.last.path == "/customers/u/usage/holds/h_1/settle")
      #expect(api.last.json?["amount"] as? Int == settled)
    }
  }

  @Test func onlyTheFirstEndingActs() async throws {
    let api = Self.holdAPI()
    try await api.run {
      let hold = try await api.server().customer("u").startHold(
        of: Self.credits, amount: 10, idempotencyKey: "job")
      try hold.use(3)
      let finished = try await hold.finish()
      let released = try await hold.release()
      let again = try await hold.finish()
      #expect(finished == released)
      #expect(finished == again)
      _ = try await hold.run { _ in 1 }
    }
    #expect(api.count == 2)
    #expect(api.last.path.hasSuffix("/settle"))
  }

  @Test func releaseFreesTheHold() async throws {
    let api = Self.holdAPI()
    try await api.run {
      let hold = try await api.server().customer("u").startHold(
        of: Self.credits, amount: 10, idempotencyKey: "job")
      let result = try await hold.release()
      #expect(result.outcome == .released)
    }
    #expect(api.last.method == "DELETE")
    #expect(api.last.path == "/customers/u/usage/holds/h_1")
  }

  @Test func finishRecordsTheExcessInObserveMode() async throws {
    let api = Self.holdAPI()
    let result = try await api.run {
      let hold = try await api.server().customer("u").startHold(
        of: Self.credits, amount: 10, idempotencyKey: "job-2")
      try hold.use(15)
      return try await hold.finish()
    }
    #expect(result.outcome == .settled)
    let requests = api.requests.get
    #expect(requests.count == 3)
    #expect(requests[1].json?["amount"] as? Int == 10)
    #expect(requests[2].path == "/customers/u/usage")
    #expect(requests[2].json?["amount"] as? Int == 5)
    #expect(requests[2].json?["mode"] as? String == "observe")
    #expect(requests[2].header("Idempotency-Key") == "job-2:excess")
  }

  @Test func anExpiredHoldIsRecordedWholeUnderTheExcessKey() async throws {
    let api = Self.holdAPI(settle: .error(409, code: "hold_expired"))
    let result = try await api.run {
      try await api.server().customer("u").withHold(
        of: Self.credits, amount: 10, idempotencyKey: "job-3"
      ) { hold in
        try hold.use(6)
        return "done"
      }
    }
    #expect(result == "done")
    #expect(api.last.path == "/customers/u/usage")
    #expect(api.last.json?["amount"] as? Int == 6)
    #expect(api.last.header("Idempotency-Key") == "job-3:excess")
  }

  @Test func withHoldAnswersTheWorksResult() async throws {
    let api = Self.holdAPI()
    let summary = try await api.run {
      try await api.server().customer("u").withHold(
        of: Self.credits, amount: 10, idempotencyKey: "job-1"
      ) { hold in
        try hold.use(9)
        try hold.use(7)
        return "summary"
      }
    }
    #expect(summary == "summary")
    #expect(
      api.requests.get.map(\.path) == [
        "/customers/u/usage/holds", "/customers/u/usage/holds/h_1/settle",
      ])
    #expect(api.last.json?["amount"] as? Int == 7)
    #expect(api.requests.get[0].header("Idempotency-Key") == "job-1")
  }

  @Test func withHoldChecksItsArguments() async throws {
    let api = Self.holdAPI()
    let customer = try api.server().customer("u")
    await #expect(
      throws: ArgumentError(message: "Pass the amount used as a whole number of 0 or more.")
    ) {
      try await api.run {
        try await customer.withHold(of: Self.credits, amount: 10, idempotencyKey: "a") { hold in
          try hold.use(-1)
        }
      }
    }
    #expect(api.last.method == "DELETE")
    await #expect(
      throws: ArgumentError(message: "Pass amount as a whole number from 1 to 9007199254740991.")
    ) {
      try await customer.withHold(of: Self.credits, amount: 0, idempotencyKey: "b") { _ in 1 }
    }
  }

  @Test func workFailingAfterReportingSettlesTheReportedAmount() async throws {
    struct WorkFailed: Error {}
    let api = Self.holdAPI()
    await #expect(throws: WorkFailed.self) {
      try await api.run {
        try await api.server().customer("u").withHold(
          of: Self.credits, amount: 10, idempotencyKey: "job"
        ) { hold in
          try hold.use(3)
          throw WorkFailed()
        }
      }
    }
    #expect(api.last.path == "/customers/u/usage/holds/h_1/settle")
    #expect(api.last.json?["amount"] as? Int == 3)
  }

  @Test func workFailingBeforeReportingReleases() async throws {
    struct WorkFailed: Error {}
    let api = Self.holdAPI()
    await #expect(throws: WorkFailed.self) {
      try await api.run {
        try await api.server().customer("u").withHold(
          of: Self.credits, amount: 10, idempotencyKey: "job"
        ) { _ in throw WorkFailed() }
      }
    }
    #expect(api.last.method == "DELETE")
    #expect(api.last.path == "/customers/u/usage/holds/h_1")
  }

  @Test func cancellingTheWorkSettlesWhatItReported() async throws {
    let api = Self.holdAPI()
    let customer = try api.server().customer("u")
    let started = Box(false)
    let task = Task {
      try await api.run {
        try await customer.withHold(of: Self.credits, amount: 10, idempotencyKey: "job") { hold in
          try hold.use(4)
          started.with { $0 = true }
          try await Task.sleep(nanoseconds: 5_000_000_000)
          return 1
        }
      }
    }
    while !started.get { try await Task.sleep(nanoseconds: 1_000_000) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(api.last.path.hasSuffix("/settle"))
    #expect(api.last.json?["amount"] as? Int == 4)
  }

  @Test func cancellingBeforeAnyReportReleases() async throws {
    let api = Self.holdAPI()
    let customer = try api.server().customer("u")
    let started = Box(false)
    let task = Task {
      try await api.run {
        try await customer.withHold(of: Self.credits, amount: 10, idempotencyKey: "job") { _ in
          started.with { $0 = true }
          try await Task.sleep(nanoseconds: 5_000_000_000)
          return 1
        }
      }
    }
    while !started.get { try await Task.sleep(nanoseconds: 1_000_000) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(api.last.method == "DELETE")
  }

  @Test func disposalFailuresGoToOnError() async throws {
    struct WorkFailed: Error {}
    for reported in [Int64?.none, 2] {
      let errors = Box<[any Error]>([])
      let api = Self.holdAPI(
        settle: .error(400, code: "invalid_body"), release: .error(404, code: "not_found"))
      let customer = try api.server { $0.onError = { error in errors.with { $0.append(error) } } }
        .customer("u")
      await #expect(throws: WorkFailed.self) {
        try await api.run {
          try await customer.withHold(of: Self.credits, amount: 10, idempotencyKey: "job") {
            hold in
            if let reported { try hold.use(reported) }
            throw WorkFailed()
          }
        }
      }
      let error = try #require(errors.get.first)
      if reported == nil {
        guard case EntitlerError.api(let api) = error else {
          Issue.record("Expected the release's own error")
          continue
        }
        #expect(api.code == .notFound)
      } else {
        guard case EntitlerError.usageSettlement(let failure) = error else {
          Issue.record("Expected a settlement error")
          continue
        }
        #expect(failure.amount == 2)
        #expect(failure.result == nil)
      }
    }
  }

  @Test func failedSettlementCarriesTheHoldAndTheResult() async throws {
    let api = Self.holdAPI(settle: .error(400, code: "invalid_body"))
    do {
      _ = try await api.run {
        try await api.server().customer("u").withHold(
          of: Self.credits, amount: 10, idempotencyKey: "job"
        ) { hold in
          try hold.use(12)
          return "output"
        }
      }
      Issue.record("Expected an error")
    } catch EntitlerError.usageSettlement(let error) {
      #expect(error.holdID == "h_1")
      #expect(error.amount == 10)
      #expect(error.excess == 2)
      #expect(error.result as? String == "output")
      #expect(error.description.contains("h_1"))
      #expect(EntitlerError.usageSettlement(error).errorDescription == error.message)
    }
  }

  @Test func finishFailingCarriesNoResult() async throws {
    let api = Self.holdAPI(record: .error(400, code: "invalid_body"))
    do {
      try await api.run {
        let hold = try await api.server().customer("u").startHold(
          of: Self.credits, amount: 10, idempotencyKey: "job")
        try hold.use(13)
        try await hold.finish()
      }
      Issue.record("Expected an error")
    } catch EntitlerError.usageSettlement(let error) {
      #expect(error.amount == 0)
      #expect(error.excess == 3)
      #expect(error.result == nil)
    }
  }

  @Test func amountsAreCheckedBeforeAnyRequest() async throws {
    let api = FakeAPI()
    let customer = try api.server().customer("u")
    await #expect(
      throws: ArgumentError(message: "Pass amount as a whole number from 1 to 9007199254740991.")
    ) {
      try await customer.recordUsage(
        of: Self.credits, amount: 9_007_199_254_740_992, idempotencyKey: "k")
    }
    await #expect(
      throws: ArgumentError(message: "Pass amount as a whole number from 0 to the held amount.")
    ) {
      try await customer.settleUsage(hold: "h", amount: -1)
    }
    #expect(api.count == 0)
  }

  @Test func usageAndItsLogPage() async throws {
    let pages = [
      #"{"items":[{"id":"u_1","feature":"ai_credits","amount":3,"kind":"use","setTo":null,"source":"client","actor":null,"at":"2026-10-09T01:47:13Z","cancelledAt":null}],"next":"c2"}"#,
      #"{"items":[],"next":"c3"}"#,
      #"{"items":[{"id":"u_2","feature":"ai_credits","amount":5,"kind":"adjust","setTo":5,"source":"dashboard","actor":"Ada","at":"2026-10-08T01:47:13Z","cancelledAt":"2026-10-08T02:00:00Z"}],"next":null}"#,
    ]
    let api = FakeAPI { request in
      let index = request.query == nil ? 0 : request.query == "cursor=c2" ? 1 : 2
      return .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","metersStartAgainAt":null,"features":[{"feature":"ai_credits","type":"metered","entitled":true,"value":300,"sources":[],"used":3,"held":0,"remaining":297,"resetsAt":null}],"log":\#(pages[index]),\#(Fixture.context)}"#
      )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let usage = try await customer.usage()
      #expect(usage.features.first?.remaining == .amount(297))
      #expect(usage.log.next == "c2")
      var ids: [String] = []
      for try await event in customer.usageLog() { ids.append(event.id) }
      #expect(ids == ["u_1", "u_2"])
      #expect(api.count == 4)
      var pageCount = 0
      for try await _ in customer.usageLog().pages { pageCount += 1 }
      #expect(pageCount == 3)
    }
  }

  @Test func usageLogRequestsPagesOnlyWhenReached() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","metersStartAgainAt":null,"features":[],"log":{"items":[{"id":"u_1","feature":"f","amount":1,"kind":"use","setTo":null,"source":"api","actor":null,"at":"2026-10-09T01:47:13Z","cancelledAt":null}],"next":"more"},\#(Fixture.context)}"#
      )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      var iterator = customer.usageLog().makeAsyncIterator()
      _ = try await iterator.next()
      #expect(api.count == 1)
    }
  }

  @Test func snapshotsAreMinted() async throws {
    let api = FakeAPI { _ in
      .json(#"{"token":"a.b.c","expiresAt":"2026-10-10T00:00:00Z","keyId":"k1"}"#, status: 201)
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let snapshot = try await customer.snapshot()
      #expect(snapshot.keyID == "k1")
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == "{}")
      #expect(api.last.header("Idempotency-Key")?.count == 36)
      _ = try await customer.snapshot(ttlSeconds: 600)
      #expect(api.last.json?["ttlSeconds"] as? Int == 600)
    }
  }
}

@Suite struct BatchTests {
  static func answering(_ request: Recorded) -> Reply {
    let events = (request.json?["events"] as? [[String: Any]]) ?? []
    let results = events.indices.map {
      #"{"index":\#($0),"outcome":"recorded","id":"u_\#($0)","late":false,"error":null}"#
    }
    return .json(
      #"{"results":[\#(results.joined(separator: ","))],"recorded":\#(events.count),"duplicates":0,"errors":0}"#
    )
  }

  static func events(_ count: Int, from start: Int = 0) -> [UsageBatchEvent] {
    (start..<start + count).map {
      UsageBatchEvent(
        customer: "c\($0)", feature: Feature<Metered>("ai_credits"), amount: 1,
        idempotencyKey: "e\($0)")
    }
  }

  @Test func batchesSplitAtFiveHundredWithKeysDerivedFromTheirEvents() async throws {
    let api = FakeAPI(Self.answering)
    let events = Self.events(1_001)
    let result = try await api.run {
      try await api.server().recordUsageBatch(events, register: true)
    }
    let requests = api.requests.get
    #expect(requests.map { ($0.json?["events"] as? [Any])?.count } == [500, 500, 1])
    #expect(result.results.count == 1_001)
    #expect(result.results.map(\.index) == Array(0..<1_001))
    #expect(result.recorded == 1_001)
    let first = try #require(requests.first?.json)
    #expect(first["register"] as? Bool == true)
    let event = try #require((first["events"] as? [[String: Any]])?.first)
    #expect(event["idempotencyKey"] as? String == "e0")
    #expect(event["customer"] as? String == "c0")
    #expect(requests.last?.path == "/usage/events")
    #expect(
      requests.last?.header("Idempotency-Key")
        == "batch:" + sha256(#"["entitler-batch-v1",true,[["c1000","ai_credits",1,null,"e1000"]]]"#)
    )
    let keys = requests.compactMap { $0.header("Idempotency-Key") }
    #expect(Set(keys).count == 3)
    #expect(keys.allSatisfy { $0.hasPrefix("batch:") && $0.count == 70 })
  }

  @Test func theSameEventsSendTheSameKeyAndARerunANewOne() async throws {
    let api = FakeAPI(Self.answering)
    let server = try api.server()
    let at = Date(timeIntervalSince1970: 1_782_898_200)
    let events = [
      UsageBatchEvent(
        customer: "a\"b", feature: Feature<Metered>("ai_credits"), amount: 2, occurredAt: at,
        idempotencyKey: "k1"),
      UsageBatchEvent(
        customer: "c", feature: Feature<Metered>("ai_credits"), amount: 3, idempotencyKey: "k2"),
    ]
    try await api.run {
      _ = try await server.recordUsageBatch(events)
      _ = try await server.recordUsageBatch(events)
      _ = try await server.recordUsageBatch([events[1]])
    }
    let keys = api.requests.get.map { $0.header("Idempotency-Key") }
    #expect(keys[0] == keys[1])
    #expect(keys[2] != keys[0])
    #expect(
      keys[0]
        == "batch:"
        + sha256(
          #"["entitler-batch-v1",false,[["a\"b","ai_credits",2,"2026-07-01T09:30:00.000Z","k1"],["c","ai_credits",3,null,"k2"]]]"#
        ))
  }

  @Test func eventsTheSDKRefusesAreAnsweredWithoutBeingSent() async throws {
    let api = FakeAPI(Self.answering)
    let events = [
      UsageBatchEvent(
        customer: " ", feature: Feature<Metered>("f"), amount: 1, idempotencyKey: "a"),
      UsageBatchEvent(customer: "c", feature: Feature<Metered>(""), amount: 1, idempotencyKey: "b"),
      UsageBatchEvent(
        customer: "c", feature: Feature<Metered>("f"), amount: 0, idempotencyKey: "c"),
      UsageBatchEvent(customer: "c", feature: Feature<Metered>("f"), amount: 1, idempotencyKey: ""),
      UsageBatchEvent(
        customer: "c", feature: Feature<Metered>("f"), amount: 1, idempotencyKey: "ok"),
    ]
    let result = try await api.run { try await api.server().recordUsageBatch(events) }
    #expect(api.count == 1)
    #expect((api.last.json?["events"] as? [Any])?.count == 1)
    #expect(result.results.map(\.outcome) == [.error, .error, .error, .error, .recorded])
    #expect(result.results[4].index == 4)
    #expect(
      result.results.prefix(4).map { $0.error?.code } == [
        .invalidBody, .invalidBody, .invalidAmount, .invalidIdempotencyKey,
      ])
    #expect(result.results[0].error?.message == "Provide the id your app uses for the customer.")
    #expect(result.results[1].error?.message == "Name the feature by its key.")
    #expect(
      result.results[2].error?.message
        == "Pass amount as a whole number from 1 to 9007199254740991.")
    #expect(
      result.results[3].error?.message
        == "Pass idempotencyKey as 1 to 200 printable ASCII characters.")
    #expect(result.errors == 4)
    let nothing = try await api.run {
      try await api.server().recordUsageBatch(Array(events.prefix(1)))
    }
    #expect(api.count == 1)
    #expect(nothing.results.count == 1)
  }

  @Test func aFailedRequestAnswersItsEventsAndTheNextStillGoes() async throws {
    let calls = Box(0)
    let api = FakeAPI { request in
      let call = calls.with {
        $0 += 1
        return $0
      }
      return call == 1 ? .failure(.cannotConnectToHost) : Self.answering(request)
    }
    let result = try await api.run {
      try await api.server { $0.maxRetries = 0 }.recordUsageBatch(Self.events(501))
    }
    #expect(api.count == 2)
    #expect(result.results.prefix(500).allSatisfy { $0.outcome == .error })
    #expect(result.results[0].error?.code == .connectionFailed)
    #expect(result.results[0].idempotencyKey == "e0")
    #expect(result.results[500].outcome == .recorded)
  }

  @Test func batchesForceRevalidationForTheirCustomers() async throws {
    let api = FakeAPI { request in
      request.method == "GET"
        ? .json(Fixture.check(), headers: ["Cache-Control": "max-age=300", "ETag": "\"e\""])
        : Self.answering(request)
    }
    let server = try api.server()
    try await api.run {
      _ = try await server.customer("u").check("sso")
      api.advance(1)
      _ = try await server.recordUsageBatch([
        UsageBatchEvent(
          customer: "u", feature: Feature<Metered>("ai_credits"), amount: 1, idempotencyKey: "k")
      ])
      _ = try await server.customer("u").check("sso")
    }
    #expect(api.count == 3)
  }

  @Test func batchErrorsAndReplaysDecode() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"results":[{"index":0,"outcome":"error","id":null,"late":false,"error":{"code":"not_metered","message":"No."}},{"index":1,"outcome":"duplicate","id":"u_1","late":true,"error":null}],"recorded":0,"duplicates":1,"errors":1}"#,
        headers: ["Idempotent-Replayed": "true"])
    }
    let result = try await api.run {
      try await api.server().recordUsageBatch([
        UsageBatchEvent(
          customer: "a", feature: Feature<Metered>("sso"), amount: 1, idempotencyKey: "x"),
        UsageBatchEvent(
          customer: "b", feature: Feature<Metered>("ai_credits"), amount: 1, idempotencyKey: "y"),
      ])
    }
    #expect(result.results[0].error?.code == .notMetered)
    #expect(result.results[1].outcome == .duplicate)
    #expect(result.results[1].replayed)
    #expect(result.duplicates == 1)
    #expect(api.last.json?["register"] == nil)
  }
}
