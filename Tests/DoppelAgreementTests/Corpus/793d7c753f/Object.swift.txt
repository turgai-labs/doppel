actor Bob {
    private var pay: Int = 3000
     private var ann: Ann = ann

    func askForRaise(amount: Int) async throws -> Bool {
        if try await ann.askForRaise(amount: amount) {
            pay += amount
            return true
        } else {
            return false
        }
    }
}
