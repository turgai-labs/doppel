actor Bob {
    var pay: Int = 3000
    
    func askForRaise(from ann: Ann, amount: Int) -> Bool {
        if ann.approveRaise(amount) {
            pay += amount
            return true
        }
        return false
    }
}
