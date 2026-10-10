//
//  HJSONValue.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// A type-safe representation of any JSON value.
///
/// Used to carry arbitrary JSON payloads in JSON-RPC requests and responses
/// (for example, the `data` field of a JSON-RPC error) without relying on `Any`.
///
/// Integers are kept exact: values that fit in `Int` decode as `.int`, and larger integers
/// (e.g. `18446744073709551615`, beyond `Int64`) decode as `.decimal` instead of losing
/// precision as a `Double`. `.decimal` holds up to 38 significant digits exactly.
///
/// The exactness of `.decimal` depends on the system `JSONDecoder`: on iOS 18 / macOS 15 and
/// later (swift-foundation) a `Decimal` is decoded from the number's digits, so they are
/// preserved exactly. On earlier OS versions (iOS 15–17, macOS 14 and earlier) `JSONDecoder`
/// decodes `Decimal` through `Double`, so an integer outside `Int`'s range may be rounded to
/// the nearest `Double`-representable value (about 16 significant digits). Encoding is exact
/// everywhere: `JSONEncoder` writes the `Decimal`'s digits as-is.
public enum HJSONValue: Sendable {
    /// A JSON `null` value.
    case null
    /// A JSON boolean value.
    case bool(Bool)
    /// A JSON integer number that fits in `Int`.
    case int(Int)
    /// A JSON integer number outside `Int`'s range (e.g. a `UInt64` above `Int.max`), re-encoded
    /// with the same digits. Up to 38 significant digits are exact when decoded on iOS 18 /
    /// macOS 15 and later; on earlier OS versions the system `JSONDecoder` goes through
    /// `Double`, so the value may be rounded (see the type documentation).
    case decimal(Decimal)
    /// A JSON floating-point number.
    case double(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array.
    case array([HJSONValue])
    /// A JSON object.
    case object([String: HJSONValue])
}

// MARK: - Equatable

extension HJSONValue: Equatable {}

// MARK: - Codable

extension HJSONValue: Codable {
    /// Decodes any JSON value. Integers that fit in `Int` decode as `.int`, larger integers as
    /// `.decimal` and other numbers as `.double`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Decimal.self), value.isIntegerOutsideIntRange {
            // An integer outside Int's range: Double would silently round it. The digits are
            // exact on iOS 18 / macOS 15 and later; earlier JSONDecoders decode Decimal via Double.
            self = .decimal(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: HJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The value is not a valid JSON value.")
        }
    }

    /// Encodes the value as the JSON it represents.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .decimal(let value):
            // JSONEncoder writes a Decimal as a number literal with its exact digits.
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSONSerialization Bridge

extension HJSONValue {
    /// The value mapped to a `JSONSerialization`-compatible object graph.
    var anyValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .decimal(let value):
            return NSDecimalNumber(decimal: value)
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map { $0.anyValue }
        case .object(let object):
            return object.mapValues { $0.anyValue }
        }
    }

    /// Creates a JSON value from a `JSONSerialization` object graph.
    /// - Parameter anyValue: An object produced by `JSONSerialization` (`NSNull`, `Bool`, `String`, `NSNumber`, `[Any]` or `[String: Any]`).
    init?(anyValue: Any) {
        switch anyValue {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let value as NSDecimalNumber:
            let decimal = value.decimalValue
            if decimal.isIntegerOutsideIntRange {
                self = .decimal(decimal)
            } else if decimal.isIntegral {
                self = .int(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .double(value.doubleValue)
            } else if Self.isUnsigned(value), value.uint64Value > UInt64(Int.max) {
                // `intValue` would wrap an unsigned value above Int.max to a negative number.
                self = .decimal(Decimal(value.uint64Value))
            } else {
                self = .int(value.intValue)
            }
        case let value as [Any]:
            self = .array(value.compactMap { HJSONValue(anyValue: $0) })
        case let value as [String: Any]:
            self = .object(value.compactMapValues { HJSONValue(anyValue: $0) })
        default:
            return nil
        }
    }

    /// Whether the number stores an unsigned integer (Objective-C type `Q`, `L`, `I`, `S` or `C`).
    private static func isUnsigned(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return ["Q", "L", "I", "S", "C"].contains(type)
    }
}

// MARK: - Decimal Helpers

/// Integer-range helpers used to classify decoded numbers.
fileprivate extension Decimal {
    /// Whether the value is an integer that does not fit in `Int`.
    var isIntegerOutsideIntRange: Bool {
        isIntegral && (self > Decimal(Int.max) || self < Decimal(Int.min))
    }

    /// Whether the value is a finite number without a fractional part.
    var isIntegral: Bool {
        guard isFinite else { return false }
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded == self
    }
}
