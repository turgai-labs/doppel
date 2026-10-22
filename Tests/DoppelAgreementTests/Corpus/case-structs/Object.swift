struct Point: Equatable {
    var x: Double
    var y: Double = 0
    let name: String

    mutating func move(by dx: Double) {
        x += dx
    }

    var length: Double { x * x + y * y }
}

actor Board {
    var points: [Point] = []

    func add() {
        var point = Point(x: 1, name: "a")
        point.move(by: 2)
        points.append(point)
        if points.contains(point) {
            print(point.length)
        }
    }

    func rename() {
        let point = Point(x: 1, y: 2, name: "b")
        point.x = 3
    }
}
