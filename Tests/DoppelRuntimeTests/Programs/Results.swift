// Result is the standard library's enum: made by its cases or by catching, read by `get()` or a
// switch, and changed by its maps.

enum Refusal: Error {
    case tooBig(Int)
    case closed
}

actor Program {
    func refund(_ amount: Int) -> Result<Int, Refusal> {
        amount > 100 ? .failure(.tooBig(amount)) : .success(amount)
    }

    func check(_ amount: Int) throws -> Int {
        if amount < 0 { throw Refusal.closed }
        return amount
    }

    func run() async {
        let small = refund(40)
        let big = refund(300)
        print(small, big)
        switch big {
        case .success(let amount): print("refunded", amount)
        case .failure(.tooBig(let amount)): print("too big", amount)
        case .failure(.closed): print("closed")
        }
        print((try? small.get()) as Any, (try? big.get()) as Any)
        print(small.map { $0 * 2 }, big.mapError { _ in Refusal.closed })
        print(small.flatMap { $0 > 30 ? refund($0 * 10) : .success($0) })
        let caught = Result { try check(-1) }
        let fine = Result { try check(5) }
        print((try? caught.get()) as Any, (try? fine.get()) as Any)
        do {
            _ = try big.get()
        } catch {
            print("threw", error)
        }
    }
}
