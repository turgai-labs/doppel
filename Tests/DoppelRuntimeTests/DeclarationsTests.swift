import Doppel
import Testing

/// The types an actor's code declares and uses, as other code meets them, as Swift resolved them.
@Suite("Declarations")
struct DeclarationsTests {
    static let module = """
        actor User {
            func getMoney() async throws -> Int { 0 }
        }
        """

    static let desk = """
        actor RefundDesk {
            /// A refund to decide on.
            struct Refund {
                var order: Int
                var reason: Reason
                /// Why, in words.
                var note: String? = nil
            }

            enum Reason: String {
                case damaged, late, wrong
            }

            /// Decides on a refund.
            func review(refund: Refund) async -> Bool { true }

            func pay(_ customer: User, amounts: [Int]) async throws {}

            private func audit() {}
        }
        """

    static func declarations() throws -> Declarations {
        let (problems, declarations) = SwiftCheck.declarations(
            of: "RefundDesk", in: "Object.swift",
            of: [.init(name: "Objects.swift", code: module), .init(name: "Object.swift", code: desk)])
        #expect(problems.isEmpty, "\(problems)")
        return try #require(declarations)
    }

    static func methods() throws -> [Declarations.Method] {
        guard case .actor(_, let methods, _, _)? = try declarations()["RefundDesk"] else { throw CancellationError() }
        return methods
    }

    @Test func methodsHaveTheirResolvedTypes() throws {
        let methods = try Self.methods()
        #expect(methods.map(\.name) == ["pay", "review"])
        let review = try #require(methods.first { $0.name == "review" })
        #expect(review.documentation == "Decides on a refund.")
        #expect(review.effects.async)
        #expect(review.result == .bool)
        let pay = try #require(methods.first { $0.name == "pay" })
        #expect(pay.parameters.map(\.label) == [nil, "amounts"])
        #expect(pay.parameters.map(\.type) == [.named("User"), .array(.int)])
    }

    @Test func valueTypesAreDeclared() throws {
        let declarations = try Self.declarations()
        let review = try #require(try Self.methods().first { $0.name == "review" })
        guard case .named(let refund, _) = review.parameters[0].type,
            case .structure(let fields, _, let documentation)? = declarations[refund]
        else {
            Issue.record("no struct for \(review.parameters[0].type): \(declarations)")
            return
        }
        #expect(documentation == "A refund to decide on.")
        #expect(fields.map(\.name) == ["order", "reason", "note"])
        #expect(fields.map(\.hasDefault) == [false, false, true])
        #expect(fields[2].type == .optional(.string))
        #expect(fields[2].documentation == "Why, in words.")
        guard case .named(let reason, _) = fields[1].type,
            case .enumeration(let cases, let conformances, _)? = declarations[reason]
        else {
            Issue.record("no enum for \(fields[1].type)")
            return
        }
        #expect(cases.map(\.name) == ["damaged", "late", "wrong"])
        #expect(cases.map(\.rawValue) == [.string("damaged"), .string("late"), .string("wrong")])
        // Swift gives an enum with raw values `Equatable` and `Hashable`.
        #expect(conformances == ["Equatable", "Hashable"])
        guard case .actor(_, let userMethods, let userConformances, _)? = declarations["User"] else {
            Issue.record("no actor User")
            return
        }
        #expect(userMethods.map(\.name) == ["getMoney"])
        #expect(userConformances == ["Actor", "Sendable"])
    }

    /// A value with its own coding keys is declared as `Codable` writes it: each property its keys
    /// name, by its key; one they leave out isn't part of it.
    @Test func codingKeysNameAValuesFields() throws {
        let code = """
            actor Station {
                struct Reading: Codable {
                    let temperature: Double
                    var note: String = ""
                    let place: String

                    enum CodingKeys: String, CodingKey {
                        case temperature = "temperature_2m"
                        case place
                    }
                }

                func record(_ reading: Reading) {}
            }
            """
        let (problems, declarations) = SwiftCheck.declarations(
            of: "Station", in: "Object.swift", of: [.init(name: "Object.swift", code: code)])
        #expect(problems.isEmpty, "\(problems)")
        guard case .structure(let fields, _, _)? = declarations?["Station.Reading"] else {
            Issue.record("no struct Station.Reading: \(String(describing: declarations))")
            return
        }
        #expect(fields.map(\.name) == ["temperature_2m", "place"])
        #expect(fields.map(\.type) == [.double, .string])
    }

    /// Foundation's types are named only where Foundation is imported, as in Swift.
    @Test(arguments: ["import Foundation\n", "import FoundationEssentials\n", ""])
    func foundationIsNamedWhereItsImported(_ imports: String) throws {
        let code = imports + "actor Ledger {\n    func record(at date: Date) -> Date { date.addingTimeInterval(60) }\n}"
        let (problems, declarations) = SwiftCheck.declarations(
            of: "Ledger", in: "Object.swift", of: [.init(name: "Object.swift", code: code)])
        if imports.isEmpty {
            #expect(problems.map(\.message).contains("cannot find type 'Date' in scope"), "\(problems)")
        } else {
            #expect(problems.isEmpty, "\(problems)")
            guard case .actor(_, let methods, _, _)? = declarations?["Ledger"] else {
                Issue.record("no actor Ledger")
                return
            }
            #expect(methods.first?.parameters.first?.type == .named("Date"))
        }
    }

    /// The protocols a type conforms to are what its declaration and its extensions say, with
    /// those they refine.
    @Test func conformancesAreDeclaredOnesAndExtensions() throws {
        let code = """
            protocol Named {}
            protocol Titled: Named {}

            struct Report: Codable {
                var count: Int
            }

            struct Note {
                var text: String
            }

            extension Note: Titled {}

            actor Desk {
                func file(report: Report, note: Note) {}
            }
            """
        let (problems, declarations) = SwiftCheck.declarations(
            of: "Desk", in: "Desk.swift", of: [.init(name: "Desk.swift", code: code)])
        #expect(problems.isEmpty, "\(problems)")
        guard case .structure(_, let report, _)? = declarations?["Report"],
            case .structure(_, let note, _)? = declarations?["Note"]
        else {
            Issue.record("no structs: \(String(describing: declarations))")
            return
        }
        #expect(report == ["Codable", "Decodable", "Encodable"])
        #expect(note == ["Named", "Titled"])
    }

    /// A type has only the types it declares, as Swift checks it: `Clerk.Note` isn't `Note`, and a
    /// name before the dot that isn't a type is a module's.
    @Test func aMemberTypeIsOnlyOneTheTypeDeclares() {
        let code = """
            actor Clerk {
                struct Slip {}
            }

            actor Desk {
                func file(note: Clerk.Note) {}
                func keep(slip: Clerk.Slip, count: Swift.Int) {}
            }
            """
        let problems = SwiftCheck.problems(in: "Desk.swift", of: [.init(name: "Desk.swift", code: code)]).map(\.message)
        #expect(problems == ["'Note' is not a member type of actor 'Clerk'"])
    }
}

/// A protocol an actor declares within it, as another actor meets it: its requirements, and who
/// conforms, checked as Swift checks it.
@Suite("Nested protocols")
struct NestedProtocolTests {
    static let shop = """
        actor Shop {
            /// Who decides on refunds.
            protocol RefundManager {
                func refundRequested(order: Int, total: Double) async throws
            }

            var managers: [any RefundManager] = []

            func startShift(manager: any RefundManager) {
                managers.append(manager)
            }
        }
        """

    @Test func anActorsProtocolIsDeclaredWithItsRequirements() throws {
        let (problems, declarations) = SwiftCheck.declarations(
            of: "Shop", in: "Object.swift", of: [.init(name: "Object.swift", code: Self.shop)])
        #expect(problems.isEmpty, "\(problems)")
        guard case .protocol(let requirements, let documentation)? = declarations?["Shop.RefundManager"] else {
            Issue.record("No Shop.RefundManager in \(String(describing: declarations?.types.keys.sorted()))")
            return
        }
        #expect(documentation == "Who decides on refunds.")
        #expect(requirements.map(\.name) == ["refundRequested"])
        #expect(requirements.first?.parameters.map(\.label) == ["order", "total"])
        #expect(requirements.first?.effects == Effects(async: true, throwing: true))
    }

    @Test func anotherActorConformsAsSwiftChecksIt() {
        func problems(_ ann: String) -> [String] {
            SwiftCheck.problems(
                in: "Object.swift",
                of: [.init(name: "Objects.swift", code: Self.shop), .init(name: "Object.swift", code: ann)]
            )
            .map(\.message)
        }
        #expect(
            problems(
                "actor Ann: Shop.RefundManager {\n    func refundRequested(order: Int, total: Double) async throws {}\n}"
            ).isEmpty)
        #expect(!problems("actor Ann: Shop.RefundManager {\n    func refundDenied(order: Int) {}\n}").isEmpty)
    }
}
