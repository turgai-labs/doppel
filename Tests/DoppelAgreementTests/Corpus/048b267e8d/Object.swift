actor CoffeeCupCounter {
    var cupCount: Int = 0
    
    func addCup() {
        cupCount += 1
    }
    
    func askCount() -> Int {
        return cupCount
    }
    
    func reset() {
        cupCount = 0
    }
}
