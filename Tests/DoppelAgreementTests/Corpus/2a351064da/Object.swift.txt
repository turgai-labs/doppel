actor Bob {
    private var pay: Int = 0
    
    init() {
        pay = 3000
    }
    
    func askForRaise(amount: Int) {
        Ann.approveRaise(amount) { approved in
            if approved {
                self.pay += amount
            }
        }
    }
}
