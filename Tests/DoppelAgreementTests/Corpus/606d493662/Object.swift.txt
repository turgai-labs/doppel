actor Ann {
    private var budget: Int = 1000

    func approveRaise(_ amount: Int) async throws {
        guard amount <= budget else {
            throw BudgetError.exceeded(amount: amount)
        }
        budget -= amount
    }

    enum BudgetError: Error {
        case exceeded(amount: Int)
    }
}
