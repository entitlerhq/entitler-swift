/// A kind of feature, which decides what a check of it answers.
public protocol FeatureKind: Sendable {
  /// What a check of this kind answers.
  associatedtype Check: Sendable
  /// The type Entitler gives features of this kind.
  static var type: FeatureType { get }
}

/// An on/off feature.
public enum Switch: FeatureKind {
  /// ``FeatureType/switch``.
  public static var type: FeatureType { .switch }
  /// A check.
  public typealias Check = Entitler.Check
}

/// A setting: an amount, or unlimited.
public enum Configuration: FeatureKind {
  /// ``FeatureType/configuration``.
  public static var type: FeatureType { .configuration }
  /// A check.
  public typealias Check = Entitler.Check
}

/// A metered feature, whose check carries its meter.
public enum Metered: FeatureKind {
  /// ``FeatureType/metered``.
  public static var type: FeatureType { .metered }
  /// A check with its meter.
  public typealias Check = MeteredCheck
}

/// A group of other features.
public enum FeatureGroup: FeatureKind {
  /// ``FeatureType/group``.
  public static var type: FeatureType { .group }
  /// A check.
  public typealias Check = Entitler.Check
}

/// A feature constant: its key and its kind, so a check answers the kind's own type.
///
/// ```swift
/// let aiCredits = Feature<Metered>("ai_credits")
/// let check = try await customer.check(aiCredits)
/// print(check.meter.remaining)
/// ```
public struct Feature<Kind: FeatureKind>: Hashable, Sendable, CustomStringConvertible {
  /// The feature's key.
  public let key: String

  /// Declares a feature by its key.
  public init(_ key: String) { self.key = key }

  /// The feature's key.
  public var description: String { key }
}
