import Foundation

actor Program {
    func run() {
        // Whole numbers from text, a slice's too, in a radix.
        let parts = "2026-11-26".split(separator: "-")
        print(Int(parts[0]) ?? -1, Int(parts[1]) ?? -1, Int(parts[2]) ?? -1)
        print(Int("ff", radix: 16) ?? -1, Int("z", radix: 36) ?? -1, Int("12", radix: 2) == nil)
        print(UInt8("255") ?? 0, UInt8("256") == nil, Int8("-128") ?? 0)
        print(Double(parts[2]) ?? 0, Double("2.5") ?? 0, Double("x") == nil)

        // Each rounding rule, on halves either side of zero and on what isn't a half.
        let rules: [FloatingPointRoundingRule] = [
            .toNearestOrAwayFromZero, .toNearestOrEven, .up, .down, .towardZero, .awayFromZero,
        ]
        for value in [2.5, -2.5, 3.5, 2.4, -2.6, 7.0] {
            print(value, value.rounded(), rules.map { value.rounded($0) })
        }

        // Rounded in place.
        var price = 9.5
        price.round()
        var span = -1.7
        span.round(.towardZero)
        var share = 0.2
        share.round(.up)
        print(price, span, share)

        // C's math, as Foundation brings it.
        for value in [2.5, -2.5, 1.2, -1.8] {
            print(floor(value), ceil(value), round(value), trunc(value))
        }

        // Whole days in a span of seconds.
        let seconds = 200_000.0
        print(Int((seconds / 86400.0).rounded(.down)), Int((seconds / 86400.0).rounded(.up)))
    }
}
