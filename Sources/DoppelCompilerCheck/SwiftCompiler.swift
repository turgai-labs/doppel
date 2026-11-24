public import Foundation

/// The Swift compiler's own verdict on code: what `swiftc` says about a module's files as it compiles them,
/// at their lines. For tests on a machine with a Swift toolchain, to hold another checker to what
/// Swift says; never shipped.
public struct SwiftCompiler: Sendable {
    /// A file of the module checked: its name, and its code.
    public struct File: Sendable {
        public let name: String
        public let code: String

        public init(name: String, code: String) {
            self.name = name
            self.code = code
        }
    }

    /// What the compiler said about a line of a file.
    public struct Diagnostic: Sendable, Equatable, CustomStringConvertible {
        public enum Severity: String, Sendable { case error, warning, note }

        public let file: String
        public let line: Int
        public let column: Int
        public let severity: Severity
        public let message: String

        public var description: String { "\(file):\(line):\(column): \(severity.rawValue): \(message)" }
    }

    /// Why the compiler couldn't be asked.
    public enum Failure: Error, CustomStringConvertible {
        case notFound
        case didNotRun(String)

        public var description: String {
            switch self {
            case .notFound: "No Swift compiler found: with `xcrun --find swiftc`, or `swiftc` on the PATH."
            case .didNotRun(let reason): "The Swift compiler didn't run: \(reason)"
            }
        }
    }

    private let executable: URL

    /// The toolchain's compiler: as `xcrun` finds it on Apple's platforms, and elsewhere the
    /// `swiftc` on the PATH.
    public init() throws(Failure) {
        #if canImport(Darwin)
            let found = try? Self.output(of: URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", "swiftc"])
        #else
            let found = try? Self.output(of: URL(fileURLWithPath: "/usr/bin/env"), ["which", "swiftc"])
        #endif
        guard let path = found?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { throw .notFound }
        executable = URL(fileURLWithPath: path)
    }

    /// What the compiler says about `files` as one module: its errors and warnings, each at the
    /// file and line it's at. Notes aren't kept.
    public func typecheck(_ files: [File], module: String = "Checked") throws(Failure) -> [Diagnostic] {
        // As the compiler writes its paths: `/private/var/…`, not `/var/…`.
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("swift-compiler-check-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var paths: [String] = []
            for file in files {
                let url = directory.appendingPathComponent(file.name)
                try file.code.write(to: url, atomically: true, encoding: .utf8)
                paths.append(url.path)
            }
            let (said, succeeded) = try Self.run(
                executable,
                // Through its mandatory passes, which say what type checking alone doesn't: a
                // constant used before it's given a value, a missing `return`.
                [
                    "-emit-sil", "-wmo", "-o", "/dev/null", "-parse-as-library", "-module-name", module,
                    "-swift-version", "6",
                    "-diagnostic-style", "llvm",
                ] + paths)
            let diagnostics = Self.diagnostics(in: said, directory: directory.path)
            // A compiler that failed says why at a file's line; one that didn't couldn't check them.
            guard succeeded || diagnostics.contains(where: { $0.severity == .error }) else {
                throw Failure.didNotRun(said)
            }
            return diagnostics
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .didNotRun(String(describing: error))
        }
    }

    /// What `files` print when they're built as a program and run: its `@main`'s output.
    public func run(_ files: [File]) throws(Failure) -> String {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("swift-compiler-run-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var paths: [String] = []
            for file in files {
                let url = directory.appendingPathComponent(file.name)
                try file.code.write(to: url, atomically: true, encoding: .utf8)
                paths.append(url.path)
            }
            let program = directory.appendingPathComponent("program")
            let (built, succeeded) = try Self.run(
                executable, ["-parse-as-library", "-swift-version", "6", "-o", program.path] + paths)
            guard succeeded else { throw Failure.didNotRun(built) }
            let (printed, ran) = try Self.run(program, [])
            guard ran else { throw Failure.didNotRun("the program stopped: \(printed)") }
            return printed
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .didNotRun(String(describing: error))
        }
    }

    /// `/dir/File.swift:3:9: error: message` lines, read as diagnostics of `File.swift`.
    static func diagnostics(in output: String, directory: String) -> [Diagnostic] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5, let number = Int(parts[1]), let column = Int(parts[2]),
                let severity = Diagnostic.Severity(rawValue: parts[3].trimmingCharacters(in: .whitespaces))
            else { return nil }
            let path = String(parts[0])
            guard path.hasPrefix(directory + "/") else { return nil }
            let file = String(path.dropFirst(directory.count + 1))
            return Diagnostic(
                file: file, line: number, column: column, severity: severity,
                message: parts[4].trimmingCharacters(in: .whitespaces))
        }
    }

    private static func output(of executable: URL, _ arguments: [String]) throws -> String {
        let (text, succeeded) = try run(executable, arguments)
        guard succeeded else { throw Failure.didNotRun(text) }
        return text
    }

    /// What `executable` writes, both streams, and whether it succeeded.
    private static func run(_ executable: URL, _ arguments: [String]) throws -> (String, Bool) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus == 0)
    }
}
