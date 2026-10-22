actor Ann {
    var budget = 1000

    func requestRaise(amount: Int) {
        if budget >= amount {
            budget -= amount
            raiseApproved(amount: amount)
        } else {
            raiseDenied(amount: amount)
        }
    }

     func raiseApproved(amount: Int) { __announce("raiseApproved", ["amount": amount]) }
     func raiseDenied(amount: Int) { __announce("raiseDenied", ["amount": amount]) }
}
