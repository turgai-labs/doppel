actor Bob {
    private var pay: Double = 3000
    
     var ann = Ann()
    
    func earnRaise(amount: Double) async throws -> Bool {
        try await ann.approveRaise(_ amount)
        if ann.approved {
            pay += amount
        }
        return true
    }
}
