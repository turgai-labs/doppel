import Foundation

actor Program {
    func run() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = Date(timeIntervalSince1970: 1_764_100_800)
        print(start.ISO8601Format())

        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        print(next.ISO8601Format(), calendar.isDate(start, inSameDayAs: next))
        let later = calendar.date(byAdding: DateComponents(month: 1, day: 6, hour: 3), to: start)!
        print(later.ISO8601Format())

        print(calendar.component(.year, from: start), calendar.component(.month, from: start))
        print(calendar.component(.day, from: start), calendar.component(.weekday, from: start))
        print(calendar.component(.hour, from: start), calendar.component(.minute, from: start))

        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        print(parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute == nil)
        print(parts.value(for: .day) ?? 0)

        let made = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        print(made.ISO8601Format())
        print(calendar.startOfDay(for: start).ISO8601Format())

        let between = calendar.dateComponents([.day, .hour], from: start, to: later)
        print(between.day ?? 0, between.hour ?? 0)

        var mutable = DateComponents()
        mutable.setValue(7, for: .day)
        mutable.hour = 9
        print(mutable.day ?? 0, mutable.hour ?? 0, mutable.month == nil)

        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        print(tokyo.identifier, tokyo.secondsFromGMT(for: start))
        print(TimeZone(identifier: "Not/AZone") == nil, TimeZone(secondsFromGMT: 3600)?.identifier ?? "none")
        print(TimeZone.gmt.identifier)

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(identifier: "UTC")!
        print(iso.firstWeekday, iso.minimumDaysInFirstWeek, calendar.firstWeekday, calendar.minimumDaysInFirstWeek)
        print(iso.component(.weekOfYear, from: start), iso.component(.yearForWeekOfYear, from: start))
        print(
            calendar.isDateInWeekend(start),
            calendar.isDateInWeekend(calendar.date(byAdding: .day, value: 3, to: start)!))

        var numbers = [5, 3, 9, 1]
        numbers.sort()
        print(numbers)
        var words = ["pear", "fig", "apple"]
        words.sort { $0.count < $1.count }
        print(words)
    }
}
