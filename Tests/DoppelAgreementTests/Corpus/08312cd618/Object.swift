actor NowPlayingBridge {
     var mediaControl = MediaControl()
     var website = Website()

    private var nowPlaying: NowPlaying?
    private var page: Page

    private let previousLabel = "Previous"
    private let nextLabel = "Next"
    private let playLabel = "▶ Play"
    private let pauseLabel = "⏸ Pause"

    init() {
        self.nowPlaying = nil
        self.page = Page(items: [
            .row(items: [
                .text(words: ""),
                .text(words: "")
            ]),
            .row(items: [
                .button(label: previousLabel),
                .button(label: playLabel),
                .button(label: nextLabel)
            ])
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
        }
    }

    func onNowPlayingChanged(nowPlaying: NowPlaying?) async {
        self.nowPlaying = nowPlaying
        let newPage = makePage()
        self.page = newPage
        try? await website.show(page: newPage)
    }

    private func makePage() -> Page {
        let artist = nowPlaying?.artist ?? ""
        let title = nowPlaying?.title ?? ""
        let isPlaying = nowPlaying?.isPlaying ?? false
        let playPauseLabel = isPlaying ? pauseLabel : playLabel

        return Page(items: [
            .row(items: [
                .text(words: artist),
                .text(words: title)
            ]),
            .row(items: [
                .button(label: previousLabel),
                .button(label: playPauseLabel),
                .button(label: nextLabel)
            ])
        ])
    }
}