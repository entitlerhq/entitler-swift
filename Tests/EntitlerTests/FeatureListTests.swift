import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct FeatureListTests {
  @Test func featuresReadTheServedVersion() async throws {
    let api = FakeAPI([
      Answer(
        headers: ["Cache-Control": "private, max-age=60"],
        body: #"""
          {"features": [
            {"id": "fe_1", "key": "storage", "kind": "FEATURE_KIND_METERED", "archived": false,
              "version": {"number": 3, "name": "Storage", "description": "Files kept", "unit": "GB",
                "sharesLimit": false, "zones": [], "measure": {"decimals": 3}}},
            {"id": "fe_2", "key": "spend", "kind": "FEATURE_KIND_METERED", "archived": false,
              "version": {"number": 1, "name": "Spend", "description": "", "unit": "",
                "sharesLimit": false, "zones": [], "measure": {"money": {}}}},
            {"id": "fe_3", "key": "legacy", "kind": "FEATURE_KIND_SWITCH", "archived": true}],
            "served": {"release": {"id": "re_1", "number": 12}}}
          """#)
    ])
    let visitor = try EntitlerVisitor(
      key: "pk_test_1", cache: MemoryCacheStore(capacity: 10),
      options: EntitlerOptions(maxRetries: 0), exchange: api.exchange, hooks: instantHooks)
    let list = try await visitor.features()
    _ = try await visitor.features()

    #expect(api.requests.count == 1)
    #expect(api.requests.first?.url?.path == "/v1/pricing/features")
    #expect(list.served.source == .release(id: "re_1", number: 12))
    let storage = list.features[0]
    #expect(storage.type == .metered)
    #expect(storage.name == "Storage")
    #expect(storage.unit == "GB")
    #expect(storage.decimals == 3)
    #expect(!storage.money)
    #expect(storage.version == 3)
    #expect(list.features[1].money)
    #expect(list.features[1].unit == nil)
    #expect(list.features[2].archived)
    #expect(list.features[2].name == nil)
    #expect(list.features[2].version == nil)
  }
}
