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
            history.insert(new, at: 0)
            if history.count > 10 {
                history.removeLast(history.count - 10)
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

        let fromLine: String
        if album.isEmpty {
            fromLine = "from \(app)"
        } else {
            fromLine = "from \(app) · \(album)"
        }

        let historyItems: [Inner] = history.map { track in
            let trackArtist = track.artist ?? ""
            let trackTitle = track.title ?? ""
            return Inner.text(words: "\(trackArtist) \(separator) \(trackTitle)")
        }

        return Page(items: [
            Item.row(items: [
                Inner.text(words: artist),
                Inner.text(words: separator),
                Inner.text(words: title)
            ]),
            Item.text(words: fromLine),
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