import Doppel
import DoppelCompilerCheck
import DoppelRuntime
import Foundation
import Testing

/// What objects' code does, run by Doppel as Swift runs it: each program here is built and
/// run by the Swift compiler too, and must print the same.
@Suite("Doppel runs code as Swift does")
struct RuntimeTests {
    @Test(
        "a program prints what Swift's build of it prints",
        arguments: [
            "Values", "Collections", "Flow", "Characters", "Protocols", "Integers", "Strings", "Functional",
            "Foundation", "Nesting", "Optionals", "Results", "EnumSelf", "NilLiterals", "AsyncSequences",
            "NestedGenerics", "Metatypes", "Streams",
        ])
    func printsAsSwiftDoes(_ name: String) async throws {
        let code = try String(contentsOf: Self.programs.appendingPathComponent("\(name).swift"), encoding: .utf8)
        let swift = try SwiftCompiler().run([
            .init(name: "Program.swift", code: code),
            .init(
                name: "Main.swift",
                code: "@main struct Main {\n    static func main() async {\n        await Program().run()\n    }\n}"),
        ])
        // The standard library's Swift, as the program uses it, has nothing wrong with it either.
        #expect(SwiftCheck.libraryProblems(in: "Program.swift", of: [.init(name: "Program.swift", code: code)]) == [])
        let host = RecordingHost()
        let object = try await LiveActor(
            type: "Program", in: "Program.swift", of: [.init(name: "Program.swift", code: code)], module: "program",
            host: host)
        _ = try await object.call("run", arguments: [])
        let ours = host.printed.split(separator: "\n", omittingEmptySubsequences: false)
        let theirs = swift.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in theirs.enumerated() where index >= ours.count || ours[index] != line {
            Issue.record(
                "line \(index + 1): Swift printed `\(line)`, Doppel `\(index < ours.count ? String(ours[index]) : "nothing")`"
            )
        }
        #expect(ours.count == theirs.count)
    }

    static let programs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Programs")
}

/// A host that answers as told and keeps what it's asked.
final class RecordingHost: ActorHost {
    let itself = ObjectHandle("itself")
    var printed = ""
    var sent: [(message: String, to: ObjectHandle, arguments: [(label: String?, value: Portable)])] = []
    var made: [String] = []
    var scheduled: [Int] = []
    var answers: [String: Portable] = [:]

    /// The type each message was sent through, in order.
    var through: [String?] = []

    func send(
        _ message: String, to object: ObjectHandle, through type: String?,
        arguments: [(label: String?, value: Portable)]
    ) async throws -> Portable {
        sent.append((message, object, arguments))
        through.append(type)
        return answers[message] ?? .null
    }

    func read(_ property: String, of object: ObjectHandle) async throws -> Portable { answers[property] ?? .null }

    func make(_ type: String, arguments: [(label: String?, value: Portable)]) async throws -> ObjectHandle {
        made.append(
            arguments.isEmpty
                ? type : "\(type)(\(arguments.map { "\($0.label ?? "_"): \($0.value)" }.joined(separator: ", ")))")
        return ObjectHandle(type)
    }

    func call(_ function: String, arguments: [(label: String?, value: Portable)]) async throws -> Portable {
        sent.append((function, ObjectHandle(""), arguments))
        return .null
    }

    func schedule(task id: Int) { scheduled.append(id) }
    func cancel(task id: Int) { scheduled.removeAll { $0 == id } }
    func print(_ text: String) { printed += text }
}

/// An object the model wrote, run against what Turgai gives it: other objects are the host's.
@Suite("Doppel runs an object against its host")
struct ObjectRunTests {
    static let bridge = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../DoppelAgreementTests/Corpus/2cc67cbff6")

    func files() throws -> [SwiftCheck.File] {
        try ["Objects.swift", "Runtime.swift", "Object.swift"].map { name in
            SwiftCheck.File(
                name: name, code: try String(contentsOf: Self.bridge.appendingPathComponent(name), encoding: .utf8))
        }
    }

    @Test(
        "a value that isn't of its type is refused with where in it, as DecodingError's coding path says",
        arguments: [
            (
                #"{"items": [{"name": "Tea", "amount": "ten"}], "reason": "early", "notes": {}}"#,
                "`refund.items[0].amount`: \"ten\" isn't an 'Int'"
            ),
            (
                #"{"items": [{"name": "Tea"}], "reason": "early", "notes": {}}"#,
                "`refund.items[0]`: an 'Item' needs 'amount'"
            ),
            (
                #"{"items": [], "reason": {"late": {"days": "two"}}, "notes": {}}"#,
                "`refund.reason.late.days`: \"two\" isn't an 'Int'"
            ),
            (
                #"{"items": [], "reason": "early", "notes": {"box": true}}"#,
                "`refund.notes[\"box\"]`: true isn't an 'Int'"
            ),
            (#"{"items": [], "reason": "soon", "notes": {}}"#, "`refund.reason`: \"soon\" isn't a case of 'Reason'"),
            (
                #"{"items": [{"name": "Tea", "amount": {"$ref": "clock"}}], "reason": "early", "notes": {}}"#,
                "`refund.items[0].amount`: <clock> isn't an 'Int'"
            ),
        ])
    func aMismatchSaysWhere(_ given: String, _ said: String) async throws {
        let code = """
            struct Item {
                let name: String
                let amount: Int
            }
            enum Reason {
                case early
                case late(days: Int)
            }
            struct Refund {
                let items: [Item]
                let reason: Reason
                let notes: [String: Int]
            }
            actor Desk {
                func refund(_ refund: Refund) {}
            }
            """
        let object = try await LiveActor(
            type: "Desk", in: "Desk.swift", of: [.init(name: "Desk.swift", code: code)], module: "desk",
            host: RecordingHost())
        let refund = Self.portable(try JSONSerialization.jsonObject(with: Data(given.utf8)))
        await #expect(throws: Trap.self) { try await object.call("refund", arguments: [(nil, refund)]) }
        do {
            _ = try await object.call("refund", arguments: [(nil, refund)])
        } catch let trap as Trap {
            #expect(trap.message == said)
        }
    }

    /// Data crosses as `Codable` writes it, as base64 text, and what isn't base64 is refused as
    /// `JSONDecoder` refuses it.
    @Test func dataCrossesAsBase64Text() async throws {
        let code = """
            import Foundation

            actor Echo {
                func reversed(_ bytes: Data) -> Data {
                    Data(bytes.reversed())
                }
            }
            """
        let object = try await LiveActor(
            type: "Echo", in: "Echo.swift", of: [.init(name: "Echo.swift", code: code)], module: "echo",
            host: RecordingHost())
        let given = Data([1, 2, 3]).base64EncodedString()
        let answer = try await object.call("reversed", arguments: [(nil, .string(given))])
        #expect(answer == .string(Data([3, 2, 1]).base64EncodedString()))
        do {
            _ = try await object.call("reversed", arguments: [(nil, .string("no!"))])
            Issue.record("text that isn't base64 was taken as data")
        } catch let trap as Trap {
            #expect(trap.message == "`bytes`: Encountered Data is not valid Base64.")
        }
    }

    /// The code of an object that takes other objects, at the top level and inside its values.
    static let teller = """
        actor Wallet {}
        actor Clock {}

        struct Refund {
            let amount: Int
            let payer: Wallet
        }

        enum Payment {
            case by(wallet: Wallet)
            case cash
        }

        actor Teller {
            func pay(wallet: Wallet) {}
            func payAll(_ wallets: [Wallet]) {}
            func refund(_ refund: Refund) {}
            func settle(_ payment: Payment) {}
            func maybe(_ wallet: Wallet?) {}
        }
        """

    @Test(
        "an object of another type is refused wherever it is in a value, with where it is",
        arguments: [
            (
                "pay", "wallet", Portable.reference(ObjectHandle("c", type: "Clock")),
                "`wallet`: a 'Clock' isn't a 'Wallet'"
            ),
            (
                "payAll", nil, .array([.reference(ObjectHandle("c", type: "Clock"))]),
                "`wallets[0]`: a 'Clock' isn't a 'Wallet'"
            ),
            (
                "refund", nil, .object([("amount", .int(5)), ("payer", .reference(ObjectHandle("c", type: "Clock")))]),
                "`refund.payer`: a 'Clock' isn't a 'Wallet'"
            ),
            (
                "settle", nil, .object([("by", .object([("wallet", .reference(ObjectHandle("c", type: "Clock")))]))]),
                "`payment.by.wallet`: a 'Clock' isn't a 'Wallet'"
            ),
            ("maybe", nil, .reference(ObjectHandle("c", type: "Clock")), "`wallet`: a 'Clock' isn't a 'Wallet'"),
        ] as [(String, String?, Portable, String)])
    func anObjectOfAnotherTypeIsRefusedWhereItIs(_ method: String, _ label: String?, _ given: Portable, _ said: String)
        async throws
    {
        let teller = try await LiveActor(
            type: "Teller", in: "Teller.swift", of: [.init(name: "Teller.swift", code: Self.teller)], module: "teller",
            host: RecordingHost())
        do {
            _ = try await teller.call(method, arguments: [(label, given)])
            Issue.record("\(method) took \(given)")
        } catch let trap as Trap {
            #expect(trap.message == said)
        }
    }

    /// An object of the type wanted is taken, and so is one whose type isn't known, which is
    /// checked when it's called.
    @Test(arguments: [ObjectHandle("w", type: "Wallet"), ObjectHandle("w")])
    func anObjectOfTheTypeOrOfNoKnownTypeIsTaken(_ handle: ObjectHandle) async throws {
        let teller = try await LiveActor(
            type: "Teller", in: "Teller.swift", of: [.init(name: "Teller.swift", code: Self.teller)], module: "teller",
            host: RecordingHost())
        _ = try await teller.call("pay", arguments: [("wallet", .reference(handle))])
        _ = try await teller.call("payAll", arguments: [(nil, .array([.reference(handle)]))])
        _ = try await teller.call(
            "refund", arguments: [(nil, .object([("amount", .int(5)), ("payer", .reference(handle))]))])
        _ = try await teller.call("maybe", arguments: [(nil, .null)])
    }

    /// JSON as a portable value, its members in their order.
    private static func portable(_ json: Any) -> Portable {
        switch json {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): .bool(number.boolValue)
        case let number as NSNumber: .int(number.intValue)
        case let text as String: .string(text)
        case let array as [Any]: .array(array.map(portable))
        case let object as [String: Any] where object.keys.sorted() == ["$ref"]:
            .reference(ObjectHandle(object["$ref"] as! String))
        case let object as [String: Any]: .object(object.keys.sorted().map { ($0, portable(object[$0]!)) })
        default: .null
        }
    }

    /// An actor another file declares is made by the host with the arguments its initializer was
    /// called with, each with its label, as Swift calls an initializer.
    @Test func aHostActorsInitializerGetsItsArguments() async throws {
        let objects = "actor Counter {\n    init(id: String)\n    func add() async throws -> Int\n}\n"
        let drinks =
            "actor Drinks {\n    let tea = Counter(id: \"tea\")\n    var other: Counter? = nil\n\n    func addCoffee() {\n        other = Counter(id: \"coffee\")\n    }\n}\n"
        let host = RecordingHost()
        let object = try await LiveActor(
            type: "Drinks", in: "Object.swift",
            of: [
                SwiftCheck.File(name: "Objects.swift", code: objects),
                SwiftCheck.File(name: "Object.swift", code: drinks),
            ],
            module: "Objects", host: host)
        #expect(host.made == ["Counter(id: \"tea\")"])
        _ = try await object.call("addCoffee", arguments: [])
        #expect(host.made == ["Counter(id: \"tea\")", "Counter(id: \"coffee\")"])
    }

    /// A function a given file declares is the host's to run, told by its name after the type
    /// it's a member of, so two of one name in two types are two functions.
    @Test func aGivenFunctionIsTheHostsByItsFullName() async throws {
        let tools =
            "enum Tools {\n    enum Web {\n        static func send(_ text: String) async throws {}\n    }\n\n    enum Mail {\n        static func send(_ text: String) async throws {}\n    }\n}\n"
        let digest =
            "actor Digest {\n    func run() async throws {\n        try await Tools.Web.send(\"page\")\n        try await Tools.Mail.send(\"note\")\n    }\n}\n"
        let host = RecordingHost()
        let object = try await LiveActor(
            type: "Digest", in: "Object.swift",
            of: [
                SwiftCheck.File(name: "Tools.swift", code: tools), SwiftCheck.File(name: "Object.swift", code: digest),
            ],
            module: "Objects", host: host)
        _ = try await object.call("run", arguments: [])
        #expect(host.sent.map(\.message) == ["Tools.Web.send", "Tools.Mail.send"])
        #expect(host.sent.map { $0.arguments.first?.value } == [.string("page"), .string("note")])
    }

    /// One actor runs here, made with the arguments it's given: another of its own type, made by
    /// its code, is another object, the host's.
    @Test func anotherOfItsOwnTypeIsTheHosts() async throws {
        let person =
            "actor Person {\n    var name = \"\"\n    var friend: Person? = nil\n\n    init(id: String) {\n        name = id\n    }\n\n    func meet() {\n        friend = Person(id: \"bob\")\n    }\n}\n"
        let host = RecordingHost()
        let object = try await LiveActor(
            type: "Person", in: "Object.swift", of: [SwiftCheck.File(name: "Object.swift", code: person)],
            module: "Objects",
            arguments: [("id", .string("ann"))], host: host)
        #expect(try object.fields().first { $0.name == "name" }?.value == .string("ann"))
        #expect(host.made.isEmpty)
        _ = try await object.call("meet", arguments: [])
        #expect(host.made == ["Person(id: \"bob\")"])
    }

    /// A requirement called on `any` of a protocol runs as the value's own type meets it: a value of
    /// this code's, with its type's method; another object, as a message sent through the protocol.
    @Test func aRequirementIsCalledOnWhatMeetsIt() async throws {
        let code = """
            protocol Greeter {
                func greet(name: String) -> String
            }

            struct Plain: Greeter {
                func greet(name: String) -> String { "Hi, " + name }
            }

            actor Desk {
                protocol Manager {
                    func refundRequested(order: Int) async throws
                }

                var managers: [any Manager] = []

                func add(manager: any Manager) {
                    managers.append(manager)
                }

                func refund(order: Int) async throws {
                    for manager in managers {
                        try await manager.refundRequested(order: order)
                    }
                }

                func greeting() -> String {
                    let greeter: any Greeter = Plain()
                    return greeter.greet(name: "Ann")
                }
            }
            """
        let host = RecordingHost()
        let desk = try await LiveActor(
            type: "Desk", in: "Object.swift", of: [SwiftCheck.File(name: "Object.swift", code: code)],
            module: "Objects", host: host)
        #expect(try await desk.call("greeting", arguments: []) == .string("Hi, Ann"))
        _ = try await desk.call("add", arguments: [("manager", .reference(ObjectHandle("ann")))])
        _ = try await desk.call("refund", arguments: [("order", .int(7))])
        #expect(host.sent.map(\.message) == ["refundRequested"])
        #expect(host.through == ["any Desk.Manager"])
    }

    /// A dictionary crosses as `Codable` writes it: keyed by `Int`, an object whose keys are the
    /// digits; keyed by anything else but `String`, its keys and values in turn.
    @Test func dictionariesCrossAsCodableWritesThem() async throws {
        let code = """
            actor Tally {
                var byDay: [Int: String] = [:]
                var byFlag: [Bool: Int] = [:]

                func take(byDay: [Int: String], byFlag: [Bool: Int]) {
                    self.byDay = byDay
                    self.byFlag = byFlag
                }

                func days() -> [Int: String] { byDay }
                func flags() -> [Bool: Int] { byFlag }
            }
            """
        let tally = try await LiveActor(
            type: "Tally", in: "Object.swift", of: [SwiftCheck.File(name: "Object.swift", code: code)],
            module: "Objects", host: RecordingHost())
        _ = try await tally.call(
            "take",
            arguments: [("byDay", .object([("3", .string("Wed"))])), ("byFlag", .array([.bool(true), .int(2)]))])
        #expect(try await tally.call("days", arguments: []) == .object([("3", .string("Wed"))]))
        #expect(try await tally.call("flags", arguments: []) == .array([.bool(true), .int(2)]))
        await #expect(throws: Trap.self) {
            try await tally.call(
                "take", arguments: [("byDay", .object([("Wed", .string("3"))])), ("byFlag", .array([]))])
        }
    }

    @Test("its objects are made by the host, and the task it starts is run by the host")
    func objectsAndTasksAreTheHosts() async throws {
        let host = RecordingHost()
        let bridge = try await LiveActor(
            type: "NowPlayingBridge", in: "Object.swift", of: try files(), module: "Objects", host: host)
        #expect(host.made == ["MediaControl", "Website", "Mac"])
        #expect(host.scheduled == [1])
        #expect(host.sent.isEmpty)
        try await bridge.runTask(1)
        #expect(host.sent.map(\.message) == ["show"])
        #expect(host.sent.first?.to == ObjectHandle("Website"))
    }

    @Test("an event it handles sends the page it makes, as Codable writes it")
    func anEventSendsThePage() async throws {
        let host = RecordingHost()
        let bridge = try await LiveActor(
            type: "NowPlayingBridge", in: "Object.swift", of: try files(), module: "Objects", host: host)
        let nowPlaying = Portable.object([
            ("app", .string("Music")), ("title", .string("Spots")), ("artist", .string("Joasihno")),
            ("album", .string("")),
            ("isPlaying", .bool(true)),
        ])
        _ = try await bridge.call("onNowPlayingChanged", arguments: [("nowPlaying", nowPlaying)])
        let shown = try #require(host.sent.last)
        #expect(shown.message == "show")
        #expect(shown.arguments.map(\.label) == ["page"])
        let text: (String) -> Portable = { .object([("text", .object([("words", .string($0))]))]) }
        let button: (String) -> Portable = { .object([("button", .object([("label", .string($0))]))]) }
        let page = Portable.object([
            (
                "items",
                .array([
                    .object([("row", .object([("items", .array([text("Joasihno"), text("—"), text("Spots")]))]))]),
                    text("from Music"),
                    .object([
                        (
                            "row",
                            .object([
                                (
                                    "items",
                                    .array([
                                        button("◀◀ Previous"), button("⏸ Pause"), button("▶▶ Next"), button("⧉ Copy"),
                                    ])
                                )
                            ])
                        )
                    ]),
                    text("Recently played"),
                    .object([("column", .object([("items", .array([text("Joasihno — Spots")]))]))]),
                ])
            )
        ])
        #expect(shown.arguments.first?.value == page)
        let history = try #require(try bridge.fields().first { $0.name == "history" }?.value)
        #expect(history == .array([nowPlaying]))
    }
}
