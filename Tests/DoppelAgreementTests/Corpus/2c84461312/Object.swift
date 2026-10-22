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
            .row(items: [
                .text(words: ""),
                .text(words: separator),
                .text(words: "")
            ]),
            .text(words: "from  · "),
            .row(items: [
                .button(label: previousLabel),
                .button(label: playLabel),
                .button(label: nextLabel),
                .button(label: copyLabel)
            ]),
            .text(words: "Recently played"),
            .column(items: [])
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
        if let new = nowPlaying,
           let old = self.nowPlaying,
           old.artist != new.artist || old.title != new.title {
            history.insert(old, at: 0)
            if history.count > 5 {
                history.removeLast(history.count - 5)
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

        let historyItems: [Inner] = history.map { track in
            let artist = track.artist ?? ""
            let title = track.title ?? ""
            return .text(words: "\(artist) \(separator) \(title)")
        }

        return Page(items: [
            .row(items: [
                .text(words: artist),
                .text(words: separator),
                .text(words: title)
            ]),
            .text(words: "from \(app) · \(album)"),
            .row(items: [
                .button(label: previousLabel),
                .button(label: playPauseLabel),
                .button(label: nextLabel),
                .button(label: copyLabel)
            ]),
            .text(words: "Recently played"),
            .column(items: historyItems)
        ])
    }
}
