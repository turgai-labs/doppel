enum Problem: Error {
    case tooLarge(Int)
}

actor Program {
    var log: [String] = []
    let limit = 10

    func check(_ amount: Int) throws -> Int {
        guard amount <= limit else { throw Problem.tooLarge(amount) }
        return amount * 2
    }

    func line(for album: String) -> String {
        let line: String
        if album.isEmpty {
            line = "from Music"
        } else {
            line = "from Music · \(album)"
        }
        return line
    }

    func describe(_ number: Int) -> String {
        switch number {
        case 0: "zero"
        case 1, 2: "small"
        default: number < 0 ? "negative" : "big"
        }
    }

    func run() async {
        print((try? check(4)) ?? -1, (try? check(40)) ?? -1)
        do {
            let doubled = try check(40)
            print("not reached", doubled)
        } catch {
            print("caught", error)
        }
        do {
            print(try check(3))
        } catch let failure {
            print("not caught", failure)
        }
        print(line(for: ""), line(for: "Spots"))
        print([0, 2, -3, 9].map(describe))
        func fibonacci(_ n: Int) -> Int {
            n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2)
        }
        print(fibonacci(10))
        var total = 0
        var i = 0
        while i < 5 {
            i += 1
            if i == 2 { continue }
            if i == 4 { break }
            total += i
        }
        print(total, i)
        var counter = 0
        let increment = { counter += 1 }
        increment()
        increment()
        print(counter)
        defer { print("deferred last") }
        defer { print("deferred first") }
        repeat {
            counter -= 1
        } while counter > 0
        print("counter", counter, 7 / 2, 7 % 3, 7.0 / 2, -5)
        print("\(3.5) \(true) \([1, 2]) \(["a"])")
    }
}
