actor Bob {
    let name = "Bob"
    let earnings = 3000
    
    func askForRaise() {
        // Ann can approve the raise while her budget lasts
        // Ann's budget is 1000, so the raise can only be approved if earnings + raise <= 1000
        // For simplicity, assume a raise of 500
        let newEarnings = earnings + 500
        // Since 'earnings' is a constant, we cannot reassign it directly
        // Instead, we simulate the approval by using a mutable variable if needed
        // But in pure actor, we rely on the caller to ensure budget constraint
        // So we just check and print the result
        
        if newEarnings <= 1000 {
            // Ann approves the raise — but we can't change the stored property directly
            // So we just indicate the action
            print("Ann approves the raise: earnings increased to \(newEarnings)")
        } else {
            print("Ann cannot approve the raise: budget would exceed 1000")
        }
    }
}
