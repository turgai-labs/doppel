actor Bob {
    private var pay: Int = 3000
    private let ann: Ann

    init() {
        self.ann = Ann()
    }

    func askForRaise(_ amount: Int) async throws {
        try await ann.approveRaise(amount)
        pay += amount
    }
}
