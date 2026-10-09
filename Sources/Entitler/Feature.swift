import Foundation

/// The type of a feature, carried by a ``Feature`` constant so each answer is typed to match.
public protocol FeatureKind: Sendable {
  /// The answer `check(_:timeout:)` gives for features of this kind.
  associatedtype Check: Decodable & Sendable
  /// The feature type the API names for this kind.
  static var type: FeatureType { get }
}

/// A feature that is on or off, such as single sign-on.
public enum OnOff: FeatureKind {
  /// Answered with a ``Entitler/Check``.
  public typealias Check = Entitler.Check
  /// ``FeatureType/boolean``.
  public static var type: FeatureType { .boolean }
}

/// A setting with an amount, such as seats.
public enum Config: FeatureKind {
  /// Answered with a ``Entitler/Check``.
  public typealias Check = Entitler.Check
  /// ``FeatureType/config``.
  public static var type: FeatureType { .config }
}

/// A feature counted against an allowance, such as AI credits.
public enum Metered: FeatureKind {
  /// Answered with a ``MeteredCheck``, which carries the meter.
  public typealias Check = MeteredCheck
  /// ``FeatureType/metered``.
  public static var type: FeatureType { .metered }
}

/// A group of other features, decided by Entitler as one.
///
/// Named `FeatureGroup` rather than `Group` so it never clashes with SwiftUI's `Group`.
public enum FeatureGroup: FeatureKind {
  /// Answered with a ``Entitler/Check``.
  public typealias Check = Entitler.Check
  /// ``FeatureType/group``.
  public static var type: FeatureType { .group }
}

/// A typed feature constant.
///
/// Generate them with `entitler generate`, or declare one by hand:
///
/// ```swift
/// enum Features {
///   static let exportPDF = Feature<OnOff>("export_pdf")
///   static let aiCredits = Feature<Metered>("ai_credits")
/// }
/// ```
public struct Feature<Kind: FeatureKind>: Hashable, Sendable, CustomStringConvertible {
  /// The feature's key, such as `export_pdf`.
  public let key: String
  /// For a group, its leaf member keys, for documentation; empty otherwise.
  public let includes: [String]

  /// Declares a feature constant by its key.
  public init(_ key: String) {
    self.key = key
    self.includes = []
  }

  /// The feature's type.
  public var type: FeatureType { Kind.type }

  /// The feature's key.
  public var description: String { key }
}

extension Feature where Kind == FeatureGroup {
  /// Declares a group constant by its key, with its leaf member keys.
  public init(_ key: String, includes: [String]) {
    self.key = key
    self.includes = includes
  }
}

/// A feature's value: on, an amount, or unlimited.
public enum FeatureValue: Hashable, Sendable, Codable, CustomStringConvertible {
  /// On (JSON `true`).
  case on
  /// An amount, `0` included.
  case amount(Int64)
  /// Unlimited (JSON `"unlimited"`).
  case unlimited

  /// Decodes `true`, a whole number from 0, or `"unlimited"`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let amount = try? container.decode(Int64.self), amount >= 0 {
      self = .amount(amount)
    } else if let on = try? container.decode(Bool.self), on {
      self = .on
    } else if let text = try? container.decode(String.self), text == "unlimited" {
      self = .unlimited
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected true, a whole number or \"unlimited\".")
    }
  }

  /// Encodes `true`, a whole number or `"unlimited"`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .on: try container.encode(true)
    case .amount(let amount): try container.encode(amount)
    case .unlimited: try container.encode("unlimited")
    }
  }

  /// `on`, the amount, or `unlimited`.
  public var description: String {
    switch self {
    case .on: "on"
    case .amount(let amount): String(amount)
    case .unlimited: "unlimited"
    }
  }
}
