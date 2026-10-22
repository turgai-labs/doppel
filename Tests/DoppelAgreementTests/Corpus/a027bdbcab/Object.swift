actor Ann {
    func startShift(manager: Object) async {
        // Ann can approve small refunds up to 50
        // Larger refunds are left for later decision
        await manager.startShift(manager: self)
    }
}
