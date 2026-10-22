actor Ann {
    func startShift(manager: Object) {
        // Ann can approve small refunds up to 50
        // Larger refunds are left for later decision
        manager.startShift(manager: self)
    }
}
