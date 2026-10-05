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
    public func count() throws -> Int { value }

    // Collections, errors, async and enums (bridged by the adapters):
    public func tags() -> [String: Int] { [label: value] }
    public func neighbors() -> [Counter] { [Counter(start: value - 1), Counter(start: value + 1)] }
    public func names(_ list: [String]) -> String { list.joined(separator: ",") }
    public func check(limit: Int) throws {
        if value > limit { throw CounterError.tooLarge(value) }
    }
    public func duplicate(named name: String) throws -> Counter {
        if name.isEmpty { throw CounterError.emptyName }
        return Counter(start: value, label: name)
    }
    public init(validating start: Int) throws {
        if start < 0 { throw CounterError.tooLarge(start) }
        value = start
        label = "validated"
    }
    public func wait() async { }
    public func fetch(id: Int) async throws -> String {
        if id < 0 { throw CounterError.emptyName }
        return "\(label)#\(id)"
    }
    public static func total(of counters: [Counter]) async -> Int { counters.reduce(0) { $0 + $1.value } }
    public var mood: Mood = .happy
    public func level() -> Level { value > 10 ? .high : .low }
    public func describe(level: Level) -> String { "level \(level.rawValue)" }
}

/// Errors thrown by `Counter`.
public enum CounterError: Error {
    case tooLarge(Int)
    case emptyName
}

/// An integer-backed enum.
public enum Level: Int {
    case low = 1, high = 5
}

/// A string-backed enum.
public enum Mood: String {
    case happy, sad
}
