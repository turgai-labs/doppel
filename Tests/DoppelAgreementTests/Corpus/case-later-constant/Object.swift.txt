actor Lines {
    var album = ""
    var app = "Music"

    func line() -> String {
        let line: String
        if album.isEmpty {
            line = "from \(app)"
        } else {
            line = "from \(app) · \(album)"
        }
        return line
    }

    func unassigned() -> String {
        let value: String
        if album.isEmpty {
            value = "none"
        }
        return value
    }
}
