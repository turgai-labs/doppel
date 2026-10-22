actor Bob {
    var pay: Int = 3000
    
    func askForRaise(from ann: Ann, amount: Int) async -> Bool {
        if await ann.approveRaise(amount) {
            pay += amount
            return true
        }
        return false
    }
}
