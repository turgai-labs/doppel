actor NowPlayingBridge {
     var mediaControl = MediaControl()
     var website = Website()
     var mac = Mac()

    private var nowPlaying: NowPlaying?
    private var history: [NowPlaying] = []
    private var page: Page
    private var separator = "—"

    private let previousLabel = "◀◀ Previous"
    private let nextLabel = "▶▶ Next"
    private let playLabel = "▶ Play"
    private let pauseLabel = "⏸ Pause"
    private let copyLabel = "⧉ Copy"

    init() {
        self.nowPlaying = nil
        self.separator = "—"
        self.page = Page(items: [
            Item.row(items: [
                Inner.text(words: ""),
                Inner.text(words: separator),
                Inner.text(words: "")
            ]),
            Item.text(words: "from  · "),
            Item.row(items: [
                Inner.button(label: previousLabel),
                Inner.button(label: playLabel),
                Inner.button(label: nextLabel),
                Inner.button(label: copyLabel)
            ]),
            Item.text(words: "Recently played"),
            Item.column(items: [])
        ])
        Task { try? await website.show(page: page) }
    }

    func onButtonPressed(label: String) async {
        if label == previousLabel {
            try? await mediaControl.previous()
        } else if label == playLabel || label == pauseLabel {
            try? await mediaControl.playPause()
        } else if label == nextLabel {
            try? await mediaControl.next()
        } else if label == copyLabel {
            let artist = nowPlaying?.artist ?? ""
            let title = nowPlaying?.title ?? ""
            try? await mac.copy(text: "\(artist) \(separator) \(title)")
        }
    }

    func onNowPlayingChanged(nowPlaying: NowPlaying?) async {
        if let new = nowPlaying {
            history.append(new)
            if history.count > 5 {
                var trimmed: [NowPlaying] = []
                let start = history.count - 5
                var i = start
                while i < history.count {
                    trimmed.append(history[i])
                    i += 1
                }
                history = trimmed
            }
        }

        self.nowPlaying = nowPlaying
        let newPage = makePage()
        self.page = newPage
        try? await website.show(page: newPage)
    }

    private func makePage() -> Page {
        let artist = nowPlaying?.artist ?? ""
        let title = nowPlaying?.title ?? ""
        let app = nowPlaying?.app ?? ""
        let album = nowPlaying?.album ?? ""
        let isPlaying = nowPlaying?.isPlaying ?? false
        let playPauseLabel = isPlaying ? pauseLabel : playLabel

        var historyItems: [Inner] = []
        var i = history.count - 1
        while i >= 0 {
            let track = history[i]
            let trackArtist = track.artist ?? ""
            let trackTitle = track.title ?? ""
            historyItems.append(Inner.text(words: "\(trackArtist) \(separator) \(trackTitle)"))
            i -= 1
        }

        return Page(items: [
            Item.row(items: [
                Inner.text(words: artist),
                Inner.text(words: separator),
                Inner.text(words: title)
            ]),
            Item.text(words: album.isEmpty ? "from \(app)" : "from \(app) · \(album)"),
            Item.row(items: [
                Inner.button(label: previousLabel),
                Inner.button(label: playPauseLabel),
                Inner.button(label: nextLabel),
                Inner.button(label: copyLabel)
            ]),
            Item.text(words: "Recently played"),
            Item.column(items: historyItems)
        ])
    }
}