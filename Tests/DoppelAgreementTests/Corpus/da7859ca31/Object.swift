actor Bob {
    private var pay: Int = 3000
    private var budget: Int = 1000
    
    func askForRaise(from ann: Ann, amount: Int) async throws {
        try await ann.approveRaise(amount)
        if budget >= amount {
            pay += amount
            budget -= amount
        } else {
            throw Bob.RaiseDenied(reason: "Budget insufficient")
        }
    }
}

// Supporting type
struct Ann {
    func approveRaise(_ amount: Int) async throws {
        if budget >= amount {
            budget -= amount
        } else {
            throw Bob.RaiseDenied(reason: "Budget insufficient")
        }
    }
}

// Error type for raise denial
struct RaiseDenied: Error {
    let reason: String
}
