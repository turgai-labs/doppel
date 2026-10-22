actor Payroll {
    let budget = 100
    var paid = 0

    func pay(_ amount: Int) -> Bool {
        guard amount <= budget - paid else { return false }
        paid += amount
        return true
    }

    func payTwice(_ amount: Double) -> Bool {
        pay(amount) && pay(amount)
    }

    func raise() {
        budget += 10
    }

    func check(_ value: Int?) -> Bool {
        if value {
            return true
        }
        return false
    }
}
