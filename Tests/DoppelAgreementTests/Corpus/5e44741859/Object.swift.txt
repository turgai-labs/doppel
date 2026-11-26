actor Bob {
    var pay: Double = 3000
    
    func askForRaise(from ann: Ann) async {
        let amount = Double(pay + ann.budget)
        await ann.approveRaise(amount: amount)
    }
}
