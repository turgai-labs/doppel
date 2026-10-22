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
    }
}
