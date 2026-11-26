actor Ann {
    private var budget: Int

    func askForRaise(ann: Object, amount: Int) -> Bool {
        budget -= amount
        return budget >= 0
    }
}
