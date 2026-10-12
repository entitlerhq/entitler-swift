import Entitler
import Foundation

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("test_1001")

let entitlements = try await customer.entitlements()
print("Export to PDF: \(entitlements.has(Features.exportPDF))")
print("Team essentials: \(entitlements.has(Features.teamEssentials))")
print("Its members: \(Features.teamEssentials.includes.joined(separator: ", "))")
let credits = try await customer.check(Features.aiCredits)
print("AI credits: \(credits.used) used, \(credits.remaining) left")
