import Foundation

struct Payment {
    var amount: Decimal
    var at: Date
    var id: UUID
}

actor Program {
    func run() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let later = start.addingTimeInterval(90)
        print(start)
        print(later.timeIntervalSince(start))
        print(start < later, later > start, start == Date(timeIntervalSince1970: 1_000_000))
        print(start + 30)
        print((later - 60).timeIntervalSince1970)
        print(start.advanced(by: 10).distance(to: later))
        print(Date(timeInterval: 5, since: start).timeIntervalSinceReferenceDate)

        let price = Decimal(string: "19.99")!
        let total = price * Decimal(3) - Decimal(1)
        print(total)
        print(total > price, total / Decimal(2))
        print(Decimal(string: "not a number") == nil)

        let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        print(id.uuidString, id)
        print(UUID(uuidString: "nope") == nil)

        let url = URL(string: "https://example.com/orders?id=7")!
        print(url.absoluteString, url.scheme ?? "none")

        let payment = Payment(amount: total, at: start, id: id)
        print(payment.amount, payment.at)

        let bytes = Data([104, 105, 33])
        print(bytes, bytes.count, bytes.isEmpty, Data().isEmpty, [bytes])
        print(bytes.base64EncodedString(), Data(base64Encoded: "aGkh") == bytes, Data(base64Encoded: "no!") == nil)
        print(String(data: bytes, encoding: .utf8) ?? "none", "héllo".data(using: .utf8)?.count ?? 0)
        var grown = Data("ab".utf8)
        grown.append(99)
        grown.append(bytes)
        grown[0] = 65
        print(Array(grown), grown.first ?? 0, grown.last ?? 0)
        let middle = grown[2..<4]
        print(middle.startIndex, middle.endIndex, middle[2], Array(middle))
        print(grown.map { Int($0) }.reduce(0) { $0 + $1 }, grown.contains(104))
        for byte in bytes.prefix(2) {
            print(byte)
        }
        grown.append(contentsOf: [1, 2])
        print(grown.count, grown.dropFirst(3).count, grown.filter { $0 > 100 }.count)
        print(Set([bytes, Data([104, 105, 33])]).count)
    }
}
