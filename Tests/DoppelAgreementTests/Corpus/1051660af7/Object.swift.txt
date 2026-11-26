actor Ann {
    var budget: Int
    
    init() {
        self.budget = 1000
    }
    
    func approveRaise(for amount: Int) -> Bool {
        return budget >= amount
    }
}

actor Bob {
    let name = "Bob"
    let earnings: Int
    
    init() {
        self.earnings = 3000
    }
    
    func askForRaise(from ann: Ann, amount: Int) -> Bool {
        return ann.approveRaise(for: amount)
    }
}
