actor Bob {
    let salary: Int = 3000
    
    func requestRaise(amount: Int) {
        Ann.approveRaise(amount) { approved in
            if approved {
                self.salary += amount
            }
        }
    }
}
