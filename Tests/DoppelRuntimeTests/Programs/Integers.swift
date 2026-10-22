actor Program {
    func fnv1a32(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for ch in text {
            hash ^= UInt32(ch.asciiValue ?? 0)
            hash = hash &* 16777619
        }
        return hash
    }

    func fnv1a64(_ values: [Int]) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for value in values {
            hash ^= UInt64(value)
            hash = hash &* 1099511628211
        }
        return hash
    }

    func hex6(_ value: UInt32) -> String {
        let hex = String(value & 0xFFFFFF, radix: 16)
        return String(repeating: "0", count: 6 - hex.count) + hex
    }

    func run() {
        let hash = fnv1a32("Blur|Tender")
        print(hash, hex6(hash), String(hash, radix: 16, uppercase: true))
        print(fnv1a64([1, 2, 3]))
        let bits = 0b1011_0110
        print(bits & 0x0F, bits | 1, bits ^ 0xFF, bits << 2, bits >> 3, ~bits)
        var mask: UInt8 = 0b1111_0000
        mask >>= 2
        mask |= 1
        mask &= 0xFE
        print(mask, UInt8.max, Int8.min, Int16.max, UInt64.max, UInt.bitWidth)
        let small: Int8 = -128
        let wrapped = Int8.max &+ 1
        print(small, wrapped, UInt8(truncatingIfNeeded: 300), UInt8(exactly: 300) == nil, Int(UInt16(65535)))
        let big: UInt64 = 1 << 63
        print(big, Double(UInt32(7)) / 2, Int32(-5) / 2, Int32(-5) % 2, UInt32(10).isMultiple(of: 5))
        print(String(255, radix: 2), String(-255, radix: 16), String(repeating: "ab", count: 3), String(repeating: Character("x"), count: 2))
        let values: [UInt8] = [3, 1, 2]
        print(values.sorted(), values.max() ?? 0, [UInt16(1): "one"][1] ?? "none")
    }
}
