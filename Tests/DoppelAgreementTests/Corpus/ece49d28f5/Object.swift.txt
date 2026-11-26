actor Bob {
    let salary: Int = 3000
    
    func requestRaise(amount: Int) {
        ann.approveRaise(amount) { approved in
            if approved {
                salary += amount
            }
        }
    }
}
