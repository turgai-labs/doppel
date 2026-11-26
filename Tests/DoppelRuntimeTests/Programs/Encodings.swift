import Foundation

actor Program {
    func run() {
        // Each of Foundation's URL sets, on every ASCII sign and on what isn't ASCII.
        let signs = " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ aZ09 é ü 日本 🙂"
        let sets: [(String, CharacterSet)] = [
            ("query", .urlQueryAllowed), ("fragment", .urlFragmentAllowed), ("path", .urlPathAllowed),
            ("host", .urlHostAllowed), ("user", .urlUserAllowed), ("password", .urlPasswordAllowed),
        ]
        for (name, set) in sets {
            print(name, signs.addingPercentEncoding(withAllowedCharacters: set) ?? "nil")
        }
        let city = "São Paulo & Köln"
        print(
            "https://example.com/search?q="
                + (city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))

        // How many of one component another holds.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let leap = calendar.date(from: DateComponents(year: 2024, month: 2, day: 10))!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26))!
        let springForward = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        for date in [leap, november, springForward] {
            let days = calendar.range(of: .day, in: .month, for: date)!
            let hours = calendar.range(of: .hour, in: .day, for: date)!
            print(days.lowerBound, days.upperBound, days.count, hours.count)
        }
        print(
            calendar.range(of: .month, in: .year, for: november).map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil")
        print(calendar.range(of: .weekday, in: .weekOfYear, for: november).map { $0.count } ?? -1)
    }
}
