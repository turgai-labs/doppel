actor CoffeeCupCounter {
    private var cupCount: Int = 0
    
    func addCup() {
        cupCount += 1
    }
    
    func getCupCount() -> Int {
        return cupCount
    }
    
    func reset() {
        cupCount = 0
    }
}
