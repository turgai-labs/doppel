actor Bob {
    var pay: Int

    init() {
        pay = 3000
    }

    func askForRaise(amount: Int) {
        if Ann.approveRaise(amount) {
            pay += amount
        }
    }
}
