actor NowPlayingBridge {
     var mediaControl = MediaControl()
     var website = Website()
     var mac = Mac()

    private struct Track: Equatable {
        let artist: String
        let title: String

        init(nowPlaying: NowPlaying) {
            self.artist = nowPlaying.artist ?? ""
            self.title = nowPlaying.title ?? ""
        }
    }

    private var nowPlaying: NowPlaying?
    private var history: [Track] = []
    private var lastTrack: Track?
    private var page: Page

    private let previousLabel = "◀◀ Previous"
    private let nextLabel = "▶▶ Next"
    private let playLabel = "▶ Play"
    private let pauseLabel = "⏸ Pause"
    private let copyLabel = "⧉ Copy"

    init() {
        self.nowPlaying = nil
        self.history = []
        self.lastTrack = nil
        self.page = Page(items: [
            Item.row(items: [
                Inner.text(words: ""),
                Inner.text(words: "—"),
                Inner.text(words: "")
            ]),
            Item.text(words: "from  — "),
            Item.row(items: [
                Inner.button(label: previousLabel),
                Inner.button(label: playLabel),
                Inner.button(label: nextLabel),
                Inner.button(label: copyLabel)
            ]),
            Item.text(words: "Recently played"),
            Item.column(items: []),
            Item.text(words: "...")
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
            try? await mac.copy(text: "\(artist) — \(title)")
        }
    }

    func onNowPlayingChanged(nowPlaying: NowPlaying?) async {
        if let newNowPlaying = nowPlaying {
            let newTrack = Track(nowPlaying: newNowPlaying)

            if let previous = lastTrack {
                if previous != newTrack {
                    history.removeAll { $0 == previous }
                    history.append(previous)
                    lastTrack = newTrack
                }
            } else {
                lastTrack = newTrack
            }

            history.removeAll { $0 == newTrack }
            if history.count > 5 {
                history.removeFirst(history.count - 5)
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
            historyItems.append(Inner.text(words: "\(track.artist) — \(track.title)"))
            i -= 1
        }

        return Page(items: [
            Item.row(items: [
                Inner.text(words: artist),
                Inner.text(words: "—"),
                Inner.text(words: title)
            ]),
            Item.text(words: album.isEmpty ? "from \(app)" : "from \(app) — \(album)"),
            Item.row(items: [
                Inner.button(label: previousLabel),
                Inner.button(label: playPauseLabel),
                Inner.button(label: nextLabel),
                Inner.button(label: copyLabel)
            ]),
            Item.text(words: "Recently played"),
            Item.column(items: historyItems),
            Item.text(words: "...")
        ])
    }
}