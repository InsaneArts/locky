import CLua
import Foundation

/// One Lua state with Locky's guards: a time budget for every call, a memory limit, and no library that
/// could end, block, or crash the lock screen. Not thread-safe: LuaRuntime uses it from one queue only.
///
/// Every function here touches the Lua stack only with raw operations that cannot raise a Lua error, and
/// runs Lua code only through `locky_pcall`. A Lua error therefore never unwinds through a Swift frame.
final class LuaVM {
    /// A Swift function Lua can call. Throwing raises a Lua error in the calling code.
    typealias Native = (LuaCall) throws -> [LuaValue]

    let state: OpaquePointer
    private let guardBox: UnsafeMutablePointer<LockyGuard>
    private var natives: [Native] = []
    /// Registry references made and not yet released.
    private(set) var liveRefs = 0

    /// Values one conversion may produce: a view tree or a config table, never a runaway structure.
    static let conversionLimit = 200_000

    init(memoryLimit: Int = 256 << 20) throws {
        guardBox = .allocate(capacity: 1)
        guardBox.initialize(to: LockyGuard())
        guardBox.pointee.soft_limit = memoryLimit
        guardBox.pointee.hard_limit = memoryLimit * 2
        guardBox.pointee.dispatch = lockyDispatch
        guard let state = locky_newstate(guardBox) else {
            guardBox.deallocate()
            throw LuaError("not enough memory to start Lua")
        }
        self.state = state
        guardBox.pointee.context = Unmanaged.passUnretained(self).toOpaque()
        locky_openlibs(state)
    }

    deinit {
        lua_close(state)
        guardBox.deinitialize(count: 1)
        guardBox.deallocate()
    }

    /// Runs `body` with the hard memory limit lifted. Locky's own pushes and registry references happen
    /// outside any protected call, where a failed allocation would abort the app. They are bounded (a
    /// process's output, a file of 16 MB at most), and the soft limit still fails the Lua code that runs next.
    func unlimited<T>(_ body: () throws -> T) rethrows -> T {
        let hard = guardBox.pointee.hard_limit
        guardBox.pointee.hard_limit = 0
        defer { guardBox.pointee.hard_limit = hard }
        return try body()
    }

    var memoryUsed: Int { Int(guardBox.pointee.used) }
    var memoryPeak: Int { Int(guardBox.pointee.peak) }

    func collectGarbage() { locky_gc_collect(state) }

    // MARK: Loading and calling

    /// Compiles Lua source. `chunkName` is what errors show, such as "@~/.config/locky/init.lua".
    func load(_ source: Data, chunkName: String) throws -> LuaRef {
        let status = source.withUnsafeBytes { bytes in
            chunkName.withCString { name in
                locky_loadbuffer(state, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count, name)
            }
        }
        guard status == LUA_OK else {
            let message = errorMessage(state)
            locky_pop(state, 1)
            throw LuaError(message)
        }
        return makeRef(state)
    }

    func load(_ source: String, chunkName: String) throws -> LuaRef {
        try load(Data(source.utf8), chunkName: chunkName)
    }

    /// Compiles a file. Errors name it with "~" for the home folder.
    func loadFile(_ url: URL) throws -> LuaRef {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LuaError("cannot read \(LuaError.shortenPaths(url.path)): \(error.localizedDescription)")
        }
        return try load(data, chunkName: "@" + LuaError.shortenPaths(url.path))
    }

    /// Calls a function under a time budget in seconds. Throws the Lua error, traceback included.
    @discardableResult
    func call(_ ref: LuaRef, _ args: [LuaValue] = [], budget: Double, allowFunctions: Bool = false) throws -> [LuaValue] {
        let L = state
        let top = lua_gettop(L)
        defer { lua_settop(L, top) }
        guard lua_checkstack(L, Int32(args.count) + 8) != 0 else { throw LuaError("Lua stack overflow") }
        lua_rawgeti(L, locky_registryindex(), lua_Integer(ref.id))
        try unlimited { for arg in args { try push(arg, in: L) } }
        let status = locky_pcall(L, Int32(args.count), LUA_MULTRET, budget)
        guard status == LUA_OK else { throw LuaError(errorMessage(L)) }
        var remaining = Self.conversionLimit
        var results: [LuaValue] = []
        for index in top + 1 ..< lua_gettop(L) + 1 {
            results.append(try value(at: index, in: L, allowFunctions: allowFunctions, remaining: &remaining))
        }
        return results
    }

    /// Runs the prelude: `chunk(natives, budget_exceeded)`. Returns the table of entry points it returns.
    func runPrelude(_ source: String, chunkName: String, natives functions: [String: Native], budget: Double) throws -> [String: LuaValue] {
        let chunk = try load(source, chunkName: chunkName)
        defer { release(chunk) }
        let L = state
        let top = lua_gettop(L)
        defer { lua_settop(L, top) }
        lua_rawgeti(L, locky_registryindex(), lua_Integer(chunk.id))
        unlimited { pushNatives(functions, in: L) }
        lua_pushcclosure(L, locky_budget_exceeded, 0)
        guard locky_pcall(L, 2, 1, budget) == LUA_OK else { throw LuaError(errorMessage(L)) }
        var remaining = Self.conversionLimit
        return try value(at: -1, in: L, allowFunctions: true, remaining: &remaining).table ?? [:]
    }

    // MARK: References

    /// Pops the value on top of `L` into the registry.
    func makeRef(_ L: OpaquePointer) -> LuaRef {
        liveRefs += 1
        return unlimited { LuaRef(id: luaL_ref(L, locky_registryindex())) }
    }

    func release(_ ref: LuaRef) {
        luaL_unref(state, locky_registryindex(), ref.id)
        liveRefs -= 1
    }

    func release(_ refs: [LuaRef]) { refs.forEach(release) }

    // MARK: Natives

    private func pushNatives(_ functions: [String: Native], in L: OpaquePointer) {
        lua_createtable(L, 0, Int32(functions.count))
        for (name, function) in functions.sorted(by: { $0.key < $1.key }) {
            natives.append(function)
            pushString(name, in: L)
            locky_pushnative(L, Int32(natives.count - 1))
            lua_rawset(L, -3)
        }
    }

    /// Runs native function `index` for the Lua code on thread `L`. Returns the number of results, or -1
    /// with an error message on top, which the C trampoline raises.
    fileprivate func dispatch(_ index: Int, _ L: OpaquePointer) -> Int32 {
        let top = lua_gettop(L)
        do {
            let results = try natives[index](LuaCall(vm: self, thread: L, count: Int(top)))
            guard lua_checkstack(L, Int32(results.count) + 8) != 0 else { throw LuaError("too many results") }
            try unlimited { for result in results { try push(result, in: L) } }
            return Int32(results.count)
        } catch {
            lua_settop(L, top)
            unlimited { pushString(String(describing: error), in: L) }
            return -1
        }
    }

    // MARK: Stack

    func push(_ value: LuaValue, in L: OpaquePointer, depth: Int = 0) throws {
        guard depth < 100, lua_checkstack(L, 4) != 0 else { throw LuaError("value nested too deeply") }
        switch value {
        case .nil: lua_pushnil(L)
        case .bool(let flag): lua_pushboolean(L, flag ? 1 : 0)
        case .int(let number): lua_pushinteger(L, lua_Integer(number))
        case .double(let number): lua_pushnumber(L, number)
        case .string(let text): pushString(text, in: L)
        case .array(let values):
            lua_createtable(L, Int32(values.count), 0)
            for (offset, element) in values.enumerated() {
                try push(element, in: L, depth: depth + 1)
                lua_rawseti(L, -2, lua_Integer(offset + 1))
            }
        case .table(let values):
            lua_createtable(L, 0, Int32(values.count))
            for (key, element) in values {
                pushString(key, in: L)
                try push(element, in: L, depth: depth + 1)
                lua_rawset(L, -3)
            }
        case .function(let ref):
            lua_rawgeti(L, locky_registryindex(), lua_Integer(ref.id))
        }
    }

    func pushString(_ text: String, in L: OpaquePointer) {
        var text = text
        text.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress { _ = lua_pushlstring(L, base, chars.count) } else { _ = lua_pushstring(L, "") }
            }
        }
    }

    func string(at index: Int32, in L: OpaquePointer) -> String {
        var length = 0
        guard let pointer = lua_tolstring(L, index, &length) else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: length), as: UTF8.self)
    }

    /// Converts the value at `index`. Functions become registry references only when `allowFunctions`;
    /// the caller then owns them.
    func value(at index: Int32, in L: OpaquePointer, allowFunctions: Bool, remaining: inout Int, depth: Int = 0) throws -> LuaValue {
        remaining -= 1
        guard remaining >= 0 else { throw LuaError("value too large: more than \(Self.conversionLimit) parts") }
        switch lua_type(L, index) {
        case LUA_TNONE, LUA_TNIL:
            return .nil
        case LUA_TBOOLEAN:
            return .bool(lua_toboolean(L, index) != 0)
        case LUA_TNUMBER:
            if lua_isinteger(L, index) != 0 { return .int(Int(lua_tointegerx(L, index, nil))) }
            return .double(lua_tonumberx(L, index, nil))
        case LUA_TSTRING:
            return .string(string(at: index, in: L))
        case LUA_TTABLE:
            return try table(at: index, in: L, allowFunctions: allowFunctions, remaining: &remaining, depth: depth + 1)
        case LUA_TFUNCTION:
            guard allowFunctions else { throw LuaError("a function cannot be used here") }
            lua_pushvalue(L, index)
            return .function(makeRef(L))
        case let type:
            throw LuaError("a \(String(cString: lua_typename(L, type))) value cannot be used here")
        }
    }

    private func table(at index: Int32, in L: OpaquePointer, allowFunctions: Bool, remaining: inout Int, depth: Int) throws -> LuaValue {
        guard depth < 64 else { throw LuaError("table nested too deeply (64 levels)") }
        guard lua_checkstack(L, 4) != 0 else { throw LuaError("Lua stack overflow") }
        let table = lua_absindex(L, index)
        let length = Int(lua_rawlen(L, table))
        var list = [LuaValue](repeating: .nil, count: length)
        var fields: [String: LuaValue] = [:]
        let top = lua_gettop(L)
        defer { lua_settop(L, top) }
        lua_pushnil(L)
        while lua_next(L, table) != 0 {
            switch lua_type(L, -2) {
            case LUA_TSTRING:
                let key = string(at: -2, in: L)
                fields[key] = try value(at: -1, in: L, allowFunctions: allowFunctions, remaining: &remaining, depth: depth)
            case LUA_TNUMBER where lua_isinteger(L, -2) != 0:
                let key = Int(lua_tointegerx(L, -2, nil))
                guard key >= 1, key <= length else {
                    throw LuaError("a table that is a list must use the keys 1, 2, 3, … without gaps")
                }
                list[key - 1] = try value(at: -1, in: L, allowFunctions: allowFunctions, remaining: &remaining, depth: depth)
            default:
                throw LuaError("table keys must be strings, or list positions 1, 2, 3, …")
            }
            locky_pop(L, 1)
        }
        if fields.isEmpty { return .array(list) }
        // A mixed table, such as { "#f00", "#00f", angle = 90 }: list items keep their positions as "1", "2", …
        for (offset, element) in list.enumerated() { fields[String(offset + 1)] = element }
        return .table(fields)
    }

    private func errorMessage(_ L: OpaquePointer) -> String {
        lua_type(L, -1) == LUA_TSTRING ? string(at: -1, in: L) : "unknown Lua error"
    }
}

/// The arguments of one call from Lua into a native function.
struct LuaCall {
    let vm: LuaVM
    let thread: OpaquePointer
    let count: Int

    /// Argument `index`, counting from 1. Functions are refused: use `function(_:)`.
    func value(_ index: Int) throws -> LuaValue {
        guard index <= count else { return .nil }
        var remaining = LuaVM.conversionLimit
        return try vm.value(at: Int32(index), in: thread, allowFunctions: false, remaining: &remaining)
    }

    func string(_ index: Int, _ name: String) throws -> String {
        guard case .string(let text) = try value(index) else { throw badArgument(index, name, "string") }
        return text
    }

    func optionalString(_ index: Int, _ name: String) throws -> String? {
        let value = try value(index)
        if value.isNil { return nil }
        guard case .string(let text) = value else { throw badArgument(index, name, "string") }
        return text
    }

    func number(_ index: Int, _ name: String) throws -> Double {
        guard let number = try value(index).number else { throw badArgument(index, name, "number") }
        return number
    }

    func table(_ index: Int, _ name: String) throws -> LuaValue {
        let value = try value(index)
        guard value.table != nil || value.array != nil else { throw badArgument(index, name, "table") }
        return value
    }

    func optionalTable(_ index: Int, _ name: String) throws -> LuaValue? {
        let value = try value(index)
        if value.isNil { return nil }
        guard value.table != nil || value.array != nil else { throw badArgument(index, name, "table") }
        return value
    }

    /// Keeps function argument `index` in the registry. The caller owns the reference and must release it.
    func function(_ index: Int, _ name: String) throws -> LuaRef {
        guard index <= count, lua_type(thread, Int32(index)) == LUA_TFUNCTION else { throw badArgument(index, name, "function") }
        lua_pushvalue(thread, Int32(index))
        return vm.makeRef(thread)
    }

    func optionalFunction(_ index: Int, _ name: String) throws -> LuaRef? {
        guard index <= count, lua_type(thread, Int32(index)) != LUA_TNIL else { return nil }
        return try function(index, name)
    }

    private func badArgument(_ index: Int, _ name: String, _ expected: String) -> LuaError {
        let actual = index <= count ? String(cString: lua_typename(thread, lua_type(thread, Int32(index)))) : "no value"
        return LuaError("bad argument #\(index) '\(name)' (\(expected) expected, got \(actual))")
    }
}

/// The C trampoline's way back into Swift.
private let lockyDispatch: LockyDispatch = { L, context, index in
    guard let L, let context else { return 0 }
    return Unmanaged<LuaVM>.fromOpaque(context).takeUnretainedValue().dispatch(Int(index), L)
}
