import Foundation

/// A function or other value kept in the Lua registry. Valid until the state closes or the owner releases it.
struct LuaRef: Hashable, Sendable {
    let id: Int32
}

/// A Lua value on the Swift side. A table with keys 1...n becomes `.array`; one with string keys, `.table`.
enum LuaValue: Sendable, Equatable {
    case `nil`
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([LuaValue])
    case table([String: LuaValue])
    case function(LuaRef)

    var isNil: Bool { self == .nil }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Integers and floats alike.
    var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    var int: Int? {
        switch self {
        case .int(let value): value
        case .double(let value) where value.rounded() == value && abs(value) < 9e15: Int(value)
        default: nil
        }
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// An empty Lua table converts to an empty array, so callers that expect a map accept both.
    var table: [String: LuaValue]? {
        switch self {
        case .table(let value): value
        case .array(let value) where value.isEmpty: [:]
        default: nil
        }
    }

    /// The list part: an array, or the "1", "2", … entries of a mixed table.
    var array: [LuaValue]? {
        switch self {
        case .array(let value):
            return value
        case .table(let value):
            var list: [LuaValue] = []
            while let element = value[String(list.count + 1)] { list.append(element) }
            return list.isEmpty && !value.isEmpty ? nil : list
        default:
            return nil
        }
    }

    var function: LuaRef? {
        if case .function(let ref) = self { return ref }
        return nil
    }

    subscript(key: String) -> LuaValue {
        table?[key] ?? .nil
    }

    subscript(index: Int) -> LuaValue {
        guard let array, array.indices.contains(index) else { return .nil }
        return array[index]
    }

    /// The Lua type name, for error messages.
    var typeName: String {
        switch self {
        case .nil: "nil"
        case .bool: "boolean"
        case .int, .double: "number"
        case .string: "string"
        case .array, .table: "table"
        case .function: "function"
        }
    }
}

extension LuaValue {
    /// From JSONSerialization output. JSON null becomes nil, which drops the key.
    init(json: Any) {
        switch json {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(LuaValue.init(json:)))
        case let object as [String: Any]:
            self = .table(object.compactMapValues { $0 is NSNull ? nil : LuaValue(json: $0) })
        default:
            self = .nil
        }
    }

    /// For JSONSerialization. Functions cannot be encoded.
    func jsonObject() throws -> Any {
        switch self {
        case .nil: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value):
            guard value.isFinite else { throw LuaError("cannot encode \(value) as JSON") }
            return value
        case .string(let value): return value
        case .array(let values): return try values.map { try $0.jsonObject() }
        case .table(let values): return try values.mapValues { try $0.jsonObject() }
        case .function: throw LuaError("cannot encode a function as JSON")
        }
    }
}

/// An error from Lua code or from a Locky function called by Lua.
struct LuaError: Error, CustomStringConvertible, Sendable, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }

    /// The first line, without the traceback: for places with room for one line.
    var summary: String {
        let first = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
        return first.hasPrefix("[string ") ? first : Self.shortenPaths(first)
    }

    /// "/Users/me/.config/locky/init.lua:3:" reads as "~/.config/locky/init.lua:3:".
    static func shortenPaths(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return text.replacingOccurrences(of: home + "/", with: "~/")
    }
}
