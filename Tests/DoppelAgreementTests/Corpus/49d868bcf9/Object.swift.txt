actor Bob {
    var pay: Int

    init() {
        pay = 3000
    }

    func askForRaise(amount: Int, from ann: Ann) {
        if ann.approveRaise(amount) {
            pay += amount
        }
    }
}
