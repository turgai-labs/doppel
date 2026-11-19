import Doppel

/// The standard library's members, as `StandardLibrary` declares them, each run as Swift runs it.
extension Evaluator {
    func standard(_ member: StandardMember, on base: Value?, _ arguments: [Value], as type: SwiftType) async throws
        -> Value
    {
        let name = member.member
        switch (member.type, base) {
        case ("", nil): return try global(name, arguments)
        case ("Task", nil) where !name.hasPrefix("init("): return try await taskStatic(name, arguments)
        case ("AsyncStream", nil), ("AsyncThrowingStream", nil):
            return try await makeStream(member.type, name, arguments)
        case (_, .stream(let box)?) where name == "makeAsyncIterator()": return .streamIterator(StreamIterator(box))
        case (_, .continuation(let box)?): return try await continuation(member, name, box, arguments)
        case ("Duration", nil) where !name.hasPrefix("init("): return try durationStatic(name, arguments)
        case ("String", nil) where name == "init(data:encoding:)",
            (_, .string?) where name == "data(using:allowLossyConversion:)":
            return try foundationString(name, base, arguments)
        case (let type, nil) where Self.jsonCoders.contains(type) && name == "init()": return .structure(type, [])
        case (_, .structure(let coder, _)?) where Self.jsonCoders.contains(coder):
            return try json(coder, name, arguments)
        case (let type, nil) where Self.foundationTypes.contains(type):
            return name.hasPrefix("init(")
                ? try foundationInitializer(type, name, arguments) : try foundationStatic(type, name)
        case (_, .date?), (_, .decimal?), (_, .uuid?), (_, .url?), (_, .data?):
            if let result = try foundationMember(name, of: base!, arguments) { return result }
        case (_, nil): return try await initializer(member.type, name, arguments)
        case (_, .array(let elements)?): return try await array(name, elements, arguments)
        case (_, .set(let elements)?): return try set(name, elements, arguments)
        case (_, .dictionary(let pairs)?): return try await dictionary(name, pairs, arguments)
        case (_, .string(let text)?): return try await string(name, text, arguments)
        case (_, .character(let character)?): return try self.character(name, character)
        case (_, .int(let number)?):
            switch name {
            case "description": return .string("\(number)")
            case "isMultiple(of:)": return .bool(number.isMultiple(of: try int(arguments[0])))
            default: break
            }
        case (_, .double(let number)?):
            switch name {
            case "description": return .string("\(number)")
            case "rounded()": return .double(number.rounded())
            default: break
            }
        case (_, .bool(let flag)?) where name == "description": return .string("\(flag)")
        case ("Unicode.Scalar", .structure(_, let fields)?):
            let scalar = try Self.unicodeScalar(fields)
            switch name {
            case "properties": return .structure("Unicode.Scalar.Properties", fields)
            case "description": return .string(String(scalar))
            case "utf8": return .array(Array(scalar.utf8).map(Self.byte))
            default: break
            }
        case ("Unicode.Scalar.Properties", .structure(_, let fields)?):
            let properties = try Self.unicodeScalar(fields).properties
            switch name {
            case "isAlphabetic": return .bool(properties.isAlphabetic)
            case "isWhitespace": return .bool(properties.isWhitespace)
            case "isUppercase": return .bool(properties.isUppercase)
            case "isLowercase": return .bool(properties.isLowercase)
            case "isEmoji": return .bool(properties.isEmoji)
            default: break
            }
        case (_, .fixed?):
            guard let integer = Integer(base!) else { break }
            switch name {
            case "description": return .string(integer.description)
            case "isMultiple(of:)":
                guard let other = Integer(arguments[0]) else { break }
                return .bool(try Self.isMultiple(integer, of: other))
            default: break
            }
        case (_, .optional(let wrapped)?):
            guard let wrapped else { return .optional(nil) }
            let result = try await apply(arguments[0], wrapped)
            if name == "flatMap(_:)" { return result }
            return .optional(result)
        case (_, .task(let task)?):
            switch name {
            case "cancel()":
                cancelTask(.task(task))
                return .void
            case "isCancelled": return .bool(false)
            default: break
            }
        default: break
        }
        throw Trap(message: "'\(member.type).\(name)' isn't run by Doppel yet")
    }

    func mutating(_ member: StandardMember, _ value: inout Value, _ arguments: [Value]) async throws -> Value {
        switch value {
        case .streamIterator(let iterator) where member.member == "next()":
            // Each waits for the stream's next value, or `nil` once it's finished.
            let next = try await iterator.box.next()
            try await ended(iterator.box)
            return .optional(next)
        case .array(var elements):
            defer { value = .array(elements) }
            switch member.member {
            case "append(_:)": elements.append(arguments[0])
            case "append(contentsOf:)": elements += try array(arguments[0])
            case "insert(_:at:)":
                let index = try int(arguments[1])
                guard index >= 0, index <= elements.count else { throw Trap(message: "Array index is out of range") }
                elements.insert(arguments[0], at: index)
            case "remove(at:)":
                let index = try int(arguments[0])
                guard elements.indices.contains(index) else { throw Trap(message: "Index out of range") }
                return elements.remove(at: index)
            case "removeFirst()":
                guard !elements.isEmpty else {
                    throw Trap(message: "Can't remove first element from an empty collection")
                }
                return elements.removeFirst()
            case "removeLast()":
                guard !elements.isEmpty else {
                    throw Trap(message: "Can't remove last element from an empty collection")
                }
                return elements.removeLast()
            case "removeFirst(_:)", "removeLast(_:)":
                let count = try int(arguments[0])
                guard count >= 0 else { throw Trap(message: "Number of elements to remove should be non-negative") }
                guard count <= elements.count else {
                    throw Trap(message: "Can't remove more items from a collection than it contains")
                }
                if member.member == "removeFirst(_:)" {
                    elements.removeFirst(count)
                } else {
                    elements.removeLast(count)
                }
            case "removeAll()": elements.removeAll()
            case "removeAll(where:)":
                var kept: [Value] = []
                for element in elements where try await !truth(of: apply(arguments[0], element)) {
                    kept.append(element)
                }
                elements = kept
            default: throw Trap(message: "'Array.\(member.member)' isn't run by Doppel yet")
            }
            return .void
        case .dictionary(var pairs):
            defer { value = .dictionary(pairs) }
            switch member.member {
            case "removeValue(forKey:)":
                guard let index = try pairs.firstIndex(where: { try Self.equal($0.key, arguments[0]) }) else {
                    return .optional(nil)
                }
                return .optional(pairs.remove(at: index).value)
            case "removeAll()": pairs.removeAll()
            default: throw Trap(message: "'Dictionary.\(member.member)' isn't run by Doppel yet")
            }
            return .void
        case .string(var text):
            defer { value = .string(text) }
            switch member.member {
            case "append(_:)":
                if case .character(let character) = arguments[0] {
                    text.append(character)
                } else {
                    text += try string(arguments[0])
                }
            case "removeFirst()":
                guard !text.isEmpty else { throw Trap(message: "Can't remove first element from an empty collection") }
                return .character(text.removeFirst())
            case "removeLast()":
                guard !text.isEmpty else { throw Trap(message: "Can't remove last element from an empty collection") }
                return .character(text.removeLast())
            case "removeFirst(_:)", "removeLast(_:)":
                let k = try int(arguments[0])
                guard k >= 0 else { throw Trap(message: "Number of elements to remove should be non-negative") }
                guard k <= text.count else {
                    throw Trap(message: "Can't remove more items from a collection than it contains")
                }
                if member.member == "removeFirst(_:)" { text.removeFirst(k) } else { text.removeLast(k) }
            case "removeAll()": text.removeAll()
            default: throw Trap(message: "'String.\(member.member)' isn't run by Doppel yet")
            }
            return .void
        case .set(var elements):
            defer { value = .set(elements) }
            switch member.member {
            case "insert(_:)":
                if let existing = try elements.first(where: { try Self.equal($0, arguments[0]) }) {
                    return .tuple([.bool(false), existing])
                }
                elements.append(arguments[0])
                return .tuple([.bool(true), arguments[0]])
            case "remove(_:)":
                guard let index = try elements.firstIndex(where: { try Self.equal($0, arguments[0]) }) else {
                    return .optional(nil)
                }
                return .optional(elements.remove(at: index))
            case "removeAll()": elements.removeAll()
            default: throw Trap(message: "'Set.\(member.member)' isn't run by Doppel yet")
            }
            return .void
        case .data(let bytes):
            guard member.member == "append(_:)" else { break }
            value = try Self.appending(arguments[0], to: bytes)
            return .void
        case .bool(let flag):
            guard member.member == "toggle()" else { break }
            value = .bool(!flag)
            return .void
        default:
            break
        }
        throw Trap(message: "'\(member.type).\(member.member)' isn't run by Doppel yet")
    }

    /// `value` with its settable standard property `member` set to `newValue`, made anew from it: a
    /// string from its Unicode scalars.
    func settingProperty(_ member: StandardMember, of value: Value, to newValue: Value) throws -> Value {
        switch (member.type, member.member, newValue) {
        case ("String", "unicodeScalars", .array(let scalars)):
            var view = String.UnicodeScalarView()
            for scalar in scalars {
                guard case .structure(_, let fields) = scalar else { throw Trap(message: "not a Unicode scalar") }
                view.append(try Self.unicodeScalar(fields))
            }
            return .string(String(view))
        default:
            throw Trap(message: "'\(member.type).\(member.member)' can't be set by Doppel yet")
        }
    }

    /// A subscript's setter: an array's element, or a dictionary's value for a key, `nil` removing it.
    func setSubscript(_ member: StandardMember, _ container: inout Value, _ keys: [Value], to value: Value) throws {
        switch container {
        case .array(var elements):
            let index = try int(keys[0])
            guard elements.indices.contains(index) else { throw Trap(message: "Index out of range") }
            elements[index] = value
            container = .array(elements)
        case .data(let bytes):
            container = try Self.setting(try int(keys[0]), of: bytes, to: value)
        case .dictionary(var pairs):
            let existing = try pairs.firstIndex { try Self.equal($0.key, keys[0]) }
            var new: Value? = value
            if member.member == "subscript(_:)", case .optional(let wrapped) = value { new = wrapped }
            switch (existing, new) {
            case (let index?, let new?): pairs[index].value = new
            case (let index?, nil): pairs.remove(at: index)
            case (nil, let new?): pairs.append((keys[0], new))
            case (nil, nil): break
            }
            container = .dictionary(pairs)
        default:
            throw Trap(message: "not a value with a subscript")
        }
    }

    // MARK: Globals and initializers

    private func global(_ name: String, _ arguments: [Value]) throws -> Value {
        switch name {
        case "print(_:separator:terminator:)":
            let items = try array(arguments[0]).map(describe)
            host.print(items.joined(separator: try string(arguments[1])) + (try string(arguments[2])))
            return .void
        case "min(_:_:)": return try Self.compare(arguments[0], arguments[1]) <= 0 ? arguments[0] : arguments[1]
        case "max(_:_:)": return try Self.compare(arguments[0], arguments[1]) >= 0 ? arguments[0] : arguments[1]
        case "abs(_:)":
            switch arguments[0] {
            case .int(let number): return .int(abs(number))
            case .double(let number): return .double(abs(number))
            default: break
            }
        case "fatalError(_:)":
            throw Trap(message: "Fatal error: \(try string(arguments[0]))")
        default: break
        }
        throw Trap(message: "'\(name)' isn't run by Doppel yet")
    }

    private func initializer(_ type: String, _ name: String, _ arguments: [Value]) async throws -> Value {
        if type == "Dictionary", name == "init(grouping:by:)" {
            var groups: [(key: Value, value: Value)] = []
            for element in try elements(of: arguments[0]) {
                let key = try await apply(arguments[1], element)
                if let index = try groups.firstIndex(where: { try Self.equal($0.key, key) }),
                    case .array(let members) = groups[index].value
                {
                    groups[index].value = .array(members + [element])
                } else {
                    groups.append((key, .array([element])))
                }
            }
            return .dictionary(groups)
        }
        // Integers as other integer types, and as text in a radix.
        let kind = FixedInteger(rawValue: type)
        if type == "Int" || kind != nil {
            if let value = Self.integerStatic(name, of: kind) { return value }
            switch (name, arguments.first) {
            case ("init(_:)", let source?), ("init(truncatingIfNeeded:)", let source?), ("init(exactly:)", let source?):
                if let whole = Integer(source) { return try integer(whole, as: kind, name) }
                if case .double(let number) = source, name == "init(_:)" { return try integer(number, as: kind) }
                if case .string(let text) = source, let kind { return Self.integer(text, as: kind) }
            default: break
            }
        }
        if type == "Double", name == "init(_:)", let source = arguments.first, case .fixed = source,
            let integer = Integer(source)
        {
            return .double(Self.double(integer))
        }
        if type == "String", name == "init(_:radix:uppercase:)", let integer = arguments.first.flatMap(Integer.init) {
            guard case .bool(let uppercase) = arguments[2] else { throw Trap(message: "not a Bool") }
            return .string(try Self.written(integer, radix: try int(arguments[1]), uppercase: uppercase))
        }
        if type == "String", name == "init(repeating:count:)" {
            let count = try int(arguments[1])
            guard count >= 0 else { throw Trap(message: "Negative count not allowed") }
            switch arguments[0] {
            case .string(let text): return .string(String(repeating: text, count: count))
            case .character(let character): return .string(String(repeating: character, count: count))
            default: throw Trap(message: "not a String or Character")
            }
        }
        switch (type, name, arguments.first) {
        case ("Int", "init(_:)", .int(let number)?): return .int(number)
        case ("Int", "init(_:)", .double(let number)?):
            guard number.isFinite, number > Double(Int.min), number < Double(Int.max) else {
                throw Trap(message: "Double value cannot be converted to Int because it is either infinite or NaN")
            }
            return .int(Int(number))
        case ("Int", "init(_:)", .string(let text)?): return .optional(Int(text).map(Value.int))
        case ("Double", "init(_:)", .int(let number)?): return .double(Double(number))
        case ("Double", "init(_:)", .double(let number)?): return .double(number)
        case ("Double", "init(_:)", .string(let text)?): return .optional(Double(text).map(Value.double))
        case ("Character", "init(_:)", .string(let text)?):
            guard text.count == 1, let character = text.first else {
                throw Trap(
                    message: "Can't form a Character from a String containing more than one extended grapheme cluster")
            }
            return .character(character)
        case ("String", "init()", _), ("Substring", "init()", _): return .string("")
        case ("String", "init(decoding:as:)", .data(let bytes)?): return .string(String(decoding: bytes, as: UTF8.self))
        case ("String", "init(decoding:as:)", let source?):
            return .string(String(decoding: try elements(of: source).map(Self.byte), as: UTF8.self))
        case ("Substring", "init(_:)", let source?):
            return .string(
                String(
                    try elements(of: source).map { value -> Character in
                        guard case .character(let character) = value else { throw Trap(message: "not a Character") }
                        return character
                    }))
        case ("Unicode.Scalar", "init(_:)", let source?):
            guard let integer = Integer(source) else { throw Trap(message: "not an integer") }
            let made = Self.scalarFrom(integer)
            if case .fixed(.uint8, _) = source { return made.map(Self.scalar) ?? .void }
            return .optional(made.map(Self.scalar))
        case ("Character", "init(_:)", .structure("Unicode.Scalar", let fields)?):
            return .character(Character(try Self.unicodeScalar(fields)))
        case ("String", "init(_:)", .structure("Unicode.Scalar", let fields)?):
            return .string(String(try Self.unicodeScalar(fields)))
        case ("Set", "init()", _): return .set([])
        case ("Set", "init(_:)", let source?): return .set(try Self.unique(try elements(of: source)))
        case ("Array", "init(_:)", .set(let elements)?): return .array(elements)
        case ("Array", "init(_:)", .string(let text)?): return .array(text.map(Value.character))
        case ("Array", "init(_:)", .data(let bytes)?): return .array(bytes.map(Self.byte))
        case ("Array", "init(repeating:count:)", let element?):
            let count = try int(arguments[1])
            guard count >= 0 else { throw Trap(message: "Can't construct Array with count < 0") }
            return .array(Array(repeating: element, count: count))
        case ("String", "init(_:)", .array(let characters)?):
            return .string(
                String(
                    try characters.map { value -> Character in
                        guard case .character(let character) = value else { throw Trap(message: "not a Character") }
                        return character
                    }))
        case ("String", "init(_:)", let value?), ("String", "init(describing:)", let value?):
            return .string(describe(value))
        case ("Array", "init()", _): return .array([])
        case ("Array", "init(_:)", .array(let elements)?): return .array(elements)
        case ("Dictionary", "init()", _): return .dictionary([])
        case ("Task", "init(operation:)", let operation?): return startTask(operation)
        case ("Int", "max", _): return .int(.max)
        case ("Int", "min", _): return .int(.min)
        default: throw Trap(message: "'\(type).\(name)' isn't run by Doppel yet")
        }
    }

    private func taskStatic(_ name: String, _ arguments: [Value]) async throws -> Value {
        switch name {
        case "sleep(for:)":
            guard case .duration(let duration) = arguments[0] else { throw Trap(message: "not a Duration") }
            try await Task.sleep(for: duration)
        case "sleep(nanoseconds:)":
            try await Task.sleep(nanoseconds: UInt64(max(0, try int(arguments[0]))))
        case "isCancelled":
            return .bool(Task.isCancelled)
        default:
            throw Trap(message: "'Task.\(name)' isn't run by Doppel yet")
        }
        return .void
    }

    private func durationStatic(_ name: String, _ arguments: [Value]) throws -> Value {
        switch (name, arguments.first) {
        case ("seconds(_:)", .int(let seconds)?): return .duration(.seconds(seconds))
        case ("seconds(_:)", .double(let seconds)?): return .duration(.seconds(seconds))
        case ("milliseconds(_:)", .int(let milliseconds)?): return .duration(.milliseconds(milliseconds))
        default: throw Trap(message: "'Duration.\(name)' isn't run by Doppel yet")
        }
    }

    // MARK: Collections

    /// An array's own members: what the collection protocols' Swift, in `StandardLibrary`, is
    /// written with.
    private func array(_ name: String, _ elements: [Value], _ arguments: [Value]) async throws -> Value {
        switch name {
        case "count": return .int(elements.count)
        case "isEmpty": return .bool(elements.isEmpty)
        case "startIndex": return .int(0)
        case "endIndex": return .int(elements.count)
        case "index(after:)": return .int(try int(arguments[0]) + 1)
        case "index(before:)": return .int(try int(arguments[0]) - 1)
        case "subscript(_:)":
            // The positions of a range, read as the array of them: the elements there.
            if case .array(let positions) = arguments[0] {
                let indices = try positions.map(int)
                guard indices.allSatisfy(elements.indices.contains) else {
                    throw Trap(message: "Array index is out of range")
                }
                return .array(indices.map { elements[$0] })
            }
            let index = try int(arguments[0])
            guard elements.indices.contains(index) else { throw Trap(message: "Index out of range") }
            return elements[index]
        default: throw Trap(message: "'Array.\(name)' isn't run by Doppel yet")
        }
    }

    /// A set's own members, what `StandardLibrary`'s Swift for sets is written with.
    private func set(_ name: String, _ elements: [Value], _ arguments: [Value]) throws -> Value {
        switch name {
        case "count": return .int(elements.count)
        case "isEmpty": return .bool(elements.isEmpty)
        case "startIndex": return .int(0)
        case "endIndex": return .int(elements.count)
        case "index(after:)": return .int(try int(arguments[0]) + 1)
        case "subscript(_:)":
            let index = try int(arguments[0])
            guard elements.indices.contains(index) else { throw Trap(message: "Set index is out of range") }
            return elements[index]
        case "contains(_:)": return .bool(try elements.contains { try Self.equal($0, arguments[0]) })
        default: throw Trap(message: "'Set.\(name)' isn't run by Doppel yet")
        }
    }

    /// A scalar as the code holds it: its `value`.
    static func scalar(_ scalar: Unicode.Scalar) -> Value {
        .structure("Unicode.Scalar", [.fixed(.uint32, UInt64(scalar.value))])
    }

    static func unicodeScalar(_ fields: [Value]) throws -> Unicode.Scalar {
        guard case .fixed(_, let bits)? = fields.first, let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: bits))
        else {
            throw Trap(message: "not a Unicode scalar")
        }
        return scalar
    }

    /// The scalar an integer is the value of, if it's one.
    static func scalarFrom(_ integer: Integer) -> Unicode.Scalar? {
        guard let value = UInt32(exactly: Double(integer.description) ?? -1) else { return nil }
        return Unicode.Scalar(value)
    }

    /// Elements, each once, in the order first met.
    static func unique(_ elements: [Value]) throws -> [Value] {
        var kept: [Value] = []
        for element in elements where try !kept.contains(where: { try equal($0, element) }) { kept.append(element) }
        return kept
    }

    private func dictionary(_ name: String, _ pairs: [(key: Value, value: Value)], _ arguments: [Value]) async throws
        -> Value
    {
        switch name {
        case "count": return .int(pairs.count)
        case "isEmpty": return .bool(pairs.isEmpty)
        case "keys": return .array(pairs.map(\.key))
        case "values": return .array(pairs.map(\.value))
        case "subscript(_:)": return .optional(try pairs.first { try Self.equal($0.key, arguments[0]) }?.value)
        case "subscript(_:default:)":
            return try pairs.first { try Self.equal($0.key, arguments[0]) }?.value ?? arguments[1]
        case "mapValues(_:)":
            var mapped: [(key: Value, value: Value)] = []
            for pair in pairs { mapped.append((pair.key, try await apply(arguments[0], pair.value))) }
            return .dictionary(mapped)
        case "filter(_:)":
            var kept: [(key: Value, value: Value)] = []
            for pair in pairs where try await truth(of: apply(arguments[0], .tuple([pair.key, pair.value]))) {
                kept.append(pair)
            }
            return .dictionary(kept)
        default: throw Trap(message: "'Dictionary.\(name)' isn't run by Doppel yet")
        }
    }

    /// A string's own members. Its index is the number of characters before it.
    private func string(_ name: String, _ text: String, _ arguments: [Value]) async throws -> Value {
        switch name {
        case "description": return .string(text)
        case "count": return .int(text.count)
        case "isEmpty": return .bool(text.isEmpty)
        case "utf8": return .array(text.utf8.map { .fixed(.uint8, UInt64($0)) })
        case "unicodeScalars": return .array(text.unicodeScalars.map(Self.scalar))
        case "startIndex": return .int(0)
        case "endIndex": return .int(text.count)
        case "index(after:)":
            let index = try int(arguments[0])
            guard index < text.count else { throw Trap(message: "String index is out of bounds") }
            return .int(index + 1)
        case "index(before:)":
            let index = try int(arguments[0])
            guard index > 0 else { throw Trap(message: "String index is out of bounds") }
            return .int(index - 1)
        case "subscript(_:)":
            let characters = Array(text)
            if case .structure("Range", let bounds) = arguments[0] {
                let (lower, upper) = (try int(bounds[0]), try int(bounds[1]))
                guard lower >= 0, upper <= characters.count else {
                    throw Trap(message: "String index range is out of bounds")
                }
                return .string(String(characters[lower..<upper]))
            }
            let index = try int(arguments[0])
            guard characters.indices.contains(index) else { throw Trap(message: "String index is out of bounds") }
            return .character(characters[index])
        case "uppercased()": return .string(text.uppercased())
        case "lowercased()": return .string(text.lowercased())
        case "hasPrefix(_:)": return .bool(text.hasPrefix(try string(arguments[0])))
        case "hasSuffix(_:)": return .bool(text.hasSuffix(try string(arguments[0])))
        case "contains(_:)":
            if case .character(let character) = arguments[0] { return .bool(text.contains(character)) }
            let other = try string(arguments[0])
            return .bool(other.isEmpty || text.contains(other))
        default: throw Trap(message: "'String.\(name)' isn't run by Doppel yet")
        }
    }

    private func character(_ name: String, _ character: Character) throws -> Value {
        switch name {
        case "description": return .string(String(character))
        case "isLetter": return .bool(character.isLetter)
        case "isNumber": return .bool(character.isNumber)
        case "isWholeNumber": return .bool(character.isWholeNumber)
        case "isWhitespace": return .bool(character.isWhitespace)
        case "isPunctuation": return .bool(character.isPunctuation)
        case "isUppercase": return .bool(character.isUppercase)
        case "isLowercase": return .bool(character.isLowercase)
        case "isASCII": return .bool(character.isASCII)
        case "wholeNumberValue": return .optional(character.wholeNumberValue.map(Value.int))
        case "asciiValue": return .optional(character.asciiValue.map { .fixed(.uint8, UInt64($0)) })
        case "uppercased()": return .string(character.uppercased())
        case "lowercased()": return .string(character.lowercased())
        default: throw Trap(message: "'Character.\(name)' isn't run by Doppel yet")
        }
    }

    // MARK: Streams

    /// A stream made as Swift makes one: given to code that yields to it, or with its continuation.
    private func makeStream(_ kind: String, _ name: String, _ arguments: [Value]) async throws -> Value {
        switch name {
        case "init(_:)":
            return try await built(StreamBox(kind: kind), arguments[0])
        case "init(_:_:)":
            return try await built(StreamBox(kind: kind), arguments[1])
        case "init(bufferingPolicy:_:)":
            return try await built(StreamBox(kind: kind, limit: try limit(arguments[0])), arguments[1])
        case "init(_:bufferingPolicy:_:)":
            return try await built(StreamBox(kind: kind, limit: try limit(arguments[1])), arguments[2])
        case "makeStream(of:)":
            let box = StreamBox(kind: kind)
            return .tuple([.stream(box), .continuation(box)])
        case "makeStream(of:bufferingPolicy:)":
            let box = StreamBox(kind: kind, limit: try limit(arguments[1]))
            return .tuple([.stream(box), .continuation(box)])
        default: throw Trap(message: "'AsyncStream.\(name)' isn't run by Doppel yet")
        }
    }

    /// The stream's handler, called once with why it ended, if it just did: then it's let go, as
    /// Swift lets go of it.
    private func ended(_ box: StreamBox) async throws {
        guard let reason = box.takeEnded(), let handler = box.onTermination else { return }
        box.onTermination = nil
        let termination = "\(box.kind).Continuation.Termination"
        switch reason {
        case .cancelled: _ = try await apply(handler, .enumCase(termination, "cancelled", []))
        case .finished(let error):
            let values: [Value] = box.kind == "AsyncThrowingStream" ? [.optional(error)] : []
            _ = try await apply(handler, .enumCase(termination, "finished", values))
        }
    }

    /// A stream, given first to the code that yields to it.
    private func built(_ box: StreamBox, _ build: Value) async throws -> Value {
        _ = try await apply(build, .continuation(box))
        return .stream(box)
    }

    /// The limit a `BufferingPolicy` says.
    private func limit(_ policy: Value) throws -> StreamBox.Limit {
        switch policy {
        case .enumCase(_, "unbounded", _): return .unbounded
        case .enumCase(_, "bufferingOldest", let values): return .oldest(max(0, try int(values[0])))
        case .enumCase(_, "bufferingNewest", let values): return .newest(max(0, try int(values[0])))
        default: throw Trap(message: "not a BufferingPolicy")
        }
    }

    /// What a stream's continuation does: a value given to whoever waits, or the stream finished.
    private func continuation(
        _ member: StandardMember, _ name: String, _ box: StreamBox, _ arguments: [Value]
    ) async throws -> Value {
        let result = "\(member.type).YieldResult"
        switch name {
        case "yield(_:)":
            switch box.yield(arguments[0]) {
            case .enqueued(let remaining): return .enumCase(result, "enqueued", [.int(remaining)])
            case .dropped(let value): return .enumCase(result, "dropped", [value])
            case .terminated: return .enumCase(result, "terminated", [])
            }
        case "finish()":
            box.finish()
            try await ended(box)
            return .void
        case "finish(throwing:)":
            if case .optional(let error?) = arguments[0] {
                box.finish(throwing: try thrown(error), error: error)
            } else {
                box.finish()
            }
            try await ended(box)
            return .void
        case "onTermination":
            return .optional(box.onTermination)
        case "onTermination=":
            if case .optional(let handler) = arguments[0] {
                box.onTermination = handler
            } else {
                box.onTermination = arguments[0]
            }
            return .void
        default: throw Trap(message: "'\(member.type).\(name)' isn't run by Doppel yet")
        }
    }

    // MARK: Helpers

    func apply(_ function: Value, _ arguments: Value...) async throws -> Value {
        guard case .function(let closure) = function else { throw Trap(message: "not a function") }
        return try await call(closure, arguments)
    }

    func truth(of value: Value) throws -> Bool {
        guard case .bool(let flag) = value else { throw Trap(message: "not a Bool") }
        return flag
    }

    func int(_ value: Value) throws -> Int {
        guard case .int(let number) = value else { throw Trap(message: "not an Int") }
        return number
    }

    func string(_ value: Value) throws -> String {
        guard case .string(let text) = value else { throw Trap(message: "not a String") }
        return text
    }

    func array(_ value: Value) throws -> [Value] {
        guard case .array(let elements) = value else { throw Trap(message: "not an Array") }
        return elements
    }
}
