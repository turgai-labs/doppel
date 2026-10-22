actor Bob {
    var salary: Int = 3000
    
    func approveRaise() {
        // Call Ann's approveRaise method
        // Ann can approve raises while her budget lasts
        // Assume Ann's budget allows the raise
        salary += 1000 // Example raise amount
    }
}
