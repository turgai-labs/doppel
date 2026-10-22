actor Bob {
    var pay: Int

    init() {
        pay = 3000
    }

    func askForRaise(amount: Int) {
        Ann.approveRaise(amount) { approved in
            if approved {
                pay += amount
            }
        }
    }
}
