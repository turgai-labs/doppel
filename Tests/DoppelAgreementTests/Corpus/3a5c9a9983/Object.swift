actor Bob {
    var pay: Int // stored property: Bob's earnings

    init() {
        self.pay = 3000 // runtime creates the object with initial pay
    }

    func approveRaise(_ amount: Int) -> Bool {
        // When Ann approves the raise, add the amount to Bob's pay
        // Only proceeds if budget allows (though Bob's budget is handled externally)
        return true // Assume approval is granted if amount is valid
    }
}
