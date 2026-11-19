import Foundation

actor Program {
    func run() {
        // Character literals, where a Character is expected.
        let character: Character = "a"
        print(character == "a", character == " ", "b" == character)
        let spaces: [Character] = [" ", "\n", "\t"]
        print(spaces.count, spaces.contains(" "), spaces.contains("x"))
        let blanks: Set<Character> = [" ", "\t"]
        print(blanks.contains(" "))

        // Text from bytes, and bytes from text.
        let bytes: [UInt8] = [104, 105, 33]
        print(String(decoding: bytes, as: UTF8.self))
        print(String(decoding: Data(bytes), as: UTF8.self))
        for scalar in "hé".unicodeScalars {
            print(scalar.value, Array(scalar.utf8))
        }

        // Unicode scalars, appended to.
        var out = ""
        for scalar in "abc".unicodeScalars { out.unicodeScalars.append(scalar) }
        out.unicodeScalars.append("!")
        print(out)

        // Splitting by text.
        let line = "a, b,, c"
        print(line.split(separator: ", "))
        print(line.split(separator: ",", omittingEmptySubsequences: false))
        print("one--two--three".split(separator: "--").joined(separator: "+"))

        // Trimming, as Foundation trims.
        print("[" + "  hi there \n".trimmingCharacters(in: .whitespacesAndNewlines) + "]")
        print("[" + "\t hi \t".trimmingCharacters(in: .whitespaces) + "]")
        print("[" + "\nhi\n".trimmingCharacters(in: .newlines) + "]")
        print("[" + "..hi, there!".trimmingCharacters(in: CharacterSet(charactersIn: ".!")) + "]")
        print(CharacterSet.whitespaces.contains(" "), CharacterSet.newlines.contains(" "))
    }
}
