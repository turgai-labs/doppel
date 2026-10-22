actor Ann {
    private let budget: Int = 1000
    
    func approveRaise(_ amount: Int) -> Bool {
        if amount <= budget {
            budget -= amount
            return true
        }
        return false
    }
}
