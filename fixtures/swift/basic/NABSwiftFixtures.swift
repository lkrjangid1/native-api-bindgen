// Synthetic Swift fixtures written for native-api-bindgen (Apache-2.0).
// Swift-only APIs (not visible to Objective-C) used to exercise symbol-graph
// discovery and @objc adapter generation.
import Foundation

/// A value type with stored and computed properties.
public struct Temperature {
    public var celsius: Double
    public init(celsius: Double) { self.celsius = celsius }
    public var fahrenheit: Double { celsius * 9 / 5 + 32 }
    public func adding(_ delta: Double) -> Temperature { Temperature(celsius: celsius + delta) }
    public mutating func reset() { celsius = 0 }
}

/// A Swift-only class (not an NSObject subclass).
public final class Counter {
    public private(set) var value: Int
    public var label: String
    public init(start: Int, label: String = "counter") {
        value = start
        self.label = label
    }
    @discardableResult
    public func increment(by step: Int) -> Int {
        value += step
        return value
    }
    public func describe(prefix: String?) -> String { "\(prefix ?? "")\(label)=\(value)" }
    public func temperature() -> Temperature { Temperature(celsius: Double(value)) }
    public func isAbove(_ threshold: Temperature) -> Bool { Double(value) > threshold.celsius }
    public static func make() -> Counter { Counter(start: 0) }
    public static var instances: Int { 0 }

    // Not adaptable to Objective-C (reported with reasons):
    public func transform(_ f: (Int) -> Int) -> Int { f(value) }
    public func pair() -> (Int, Int) { (value, value) }
    public func identity<T>(_ x: T) -> T { x }
    public func later() async -> Int { value }
    public func values() -> [Int] { [value] }
}

/// A string-backed enum.
public enum Mood: String {
    case happy, sad
}
