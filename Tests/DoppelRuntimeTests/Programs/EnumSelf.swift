// An enum's initializers and mutating methods set `self` to one of its cases, a generic one's too.

enum Box {
    case full(Int)
    case empty

    init(number: Int) {
        self = .full(number)
    }

    init(trying body: () throws -> Int) {
        do {
            self = .full(try body())
        } catch {
            self = .empty
        }
    }
}

enum Holder<Value> {
    case held(Value)
    init(making body: () -> Value) {
        self = .held(body())
    }
}

enum Light {
    case on, off

    mutating func flip() {
        self = self == .on ? .off : .on
    }
}

actor Program {
    func run() async {
        print(Box(number: 3))
        print(Box { 4 })
        print(Holder { "x" })
        print(Result<Int, any Error>(catching: { 5 }))
        var light = Light.on
        light.flip()
        print(light)
    }
}
