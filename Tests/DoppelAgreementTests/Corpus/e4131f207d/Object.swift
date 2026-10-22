actor Bob {
    // Stored properties are what it keeps
    var pendingRefunds: [Int: Double] = [:]

    func handleRefund(amount: Double) -> Bool {
        if amount <= 20 {
            return true // Approve small refunds on his own
        } else {
            // Keep larger ones for the owner to decide later
            pendingRefunds[amount] = amount
            return false
        }
    }
}
