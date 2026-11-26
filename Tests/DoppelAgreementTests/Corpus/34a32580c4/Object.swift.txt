actor MediaBridge {
     var mediaControl = MediaControl()
     var website = Website()

    func onButtonPressed(label: String) async {
        switch label {
        case "Prev":
            await mediaControl.previous()
        case "Play", "Pause", "Play/Pause":
            await mediaControl.playPause()
        case "Next":
            await mediaControl.next()
        default:
            break
        }
    }

    func onNowPlayingChanged(nowPlaying: [String: Any]?) async {
        await website.show(page: page(for: nowPlaying))
    }

    func render() async {
        let nowPlaying = await mediaControl.nowPlaying
        await website.show(page: page(for: nowPlaying))
    }

    private func page(for nowPlaying: [String: Any]?) -> [String: Any] {
        let artist = nowPlaying?["artist"] as? String ?? ""
        let song = nowPlaying?["title"] as? String ?? ""
        let isPlaying = nowPlaying?["isPlaying"] as? Bool ?? false
        let playPauseLabel = isPlaying ? "Pause" : "Play"

        return [
            "rows": [
                [
                    "columns": [
                        ["type": "text", "text": artist],
                        ["type": "text", "text": song]
                    ]
                ],
                [
                    "columns": [
                        ["type": "button", "label": "Prev"],
                        ["type": "button", "label": playPauseLabel],
                        ["type": "button", "label": "Next"]
                    ]
                ]
            ]
        ]
    }
}
