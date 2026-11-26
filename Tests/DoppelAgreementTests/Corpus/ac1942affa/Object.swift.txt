actor CoffeeCupCounter {
    private var count: Int = 0
    
    func add(_ amount: Int) async {
        self.count += amount
    }
    
    func currentCount() async -> Int {
        return self.count
    }
    
    func reset() async {
        self.count = 0
    }
}
