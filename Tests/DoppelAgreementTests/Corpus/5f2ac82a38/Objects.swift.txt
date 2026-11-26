/// This Mac: its clipboard, battery, and how hard it's working.
actor Mac {
    /// The battery, or null on a Mac without one.
    var battery: Battery? { get async throws  {fatalError() }}
    /// The text on the clipboard, or null when it holds no text.
    var clipboard: String? { get async throws  {fatalError() }}
    /// The computer's name, such as "Ada's MacBook Pro".
    var name: String { get async throws  {fatalError() }}
    /// How hot the Mac is running. Above nominal, the system slows work down.
    var thermalState: ThermalState { get async throws  {fatalError() }}
    /// Put text on the clipboard, replacing what's there.
    /// - Parameter text: The text to copy.
    func copy(text: String) async throws {fatalError()}
}

/// The media playing on this machine, in whichever app plays it: what's playing, and the keyboard's media keys.
actor MediaControl {
    /// What's playing, or null when nothing is.
    var nowPlaying: NowPlaying? { get async throws  {fatalError() }}
    /// Skip to the next track.
    func next() async throws {fatalError()}
    /// Play what's paused, or pause what's playing.
    func playPause() async throws {fatalError()}
    /// Go back to the previous track.
    func previous() async throws {fatalError()}
    func nowPlayingChanged(nowPlaying: NowPlaying?) {fatalError()}
}

/// A website on this machine: one page of rows, columns, texts and buttons. A page shown replaces the one before in every open browser, and a button pressed there is announced.
actor Website {
    /// Where the website is, to open in a browser.
    var address: String { get async throws  {fatalError() }}
    /// The page it shows.
    var page: Page { get async throws  {fatalError() }}
    /// Show a page in place of the current one, in every open browser too. To change the page, send the current one with your changes.
    /// - Parameter page: The page to show.
    func show(page: Page) async throws {fatalError()}
    func buttonPressed(label: String) {fatalError()}
}

/// A Mac's battery.
struct Battery {
    /// Charge, from 0 to 100.
    var level: Int
    /// Whether it's charging now.
    var isCharging: Bool
    /// Whether the Mac is connected to power.
    var isOnPower: Bool
}

/// How hot the Mac is running. Above nominal, the system slows work down.
enum ThermalState: String {
    /// Normal.
    case nominal
    /// Slightly elevated.
    case fair
    /// High; the system reduces performance.
    case serious
    /// Very high; the system reduces performance significantly.
    case critical
}

/// What's playing, in which app.
struct NowPlaying {
    /// The app playing it.
    var app: String
    var title: String?
    var artist: String?
    var album: String?
    /// Whether it's playing now, or paused.
    var isPlaying: Bool
}

/// The page it shows.
struct Page {
    /// What it shows, top to bottom.
    var items: [Item]
}

/// Something a page shows.
enum Item {
    /// Words to read.
    case text(words: String)
    /// A button. Pressing it announces ButtonPressed with its label.
    case button(label: String)
    /// Things side by side, left to right.
    case row(items: [Inner])
    /// Things one under another, top to bottom.
    case column(items: [Inner])
}

/// Something inside a row or a column.
enum Inner {
    /// Words to read.
    case text(words: String)
    /// A button. Pressing it announces ButtonPressed with its label.
    case button(label: String)
    /// Things side by side, left to right.
    case row(items: [Leaf])
    /// Things one under another, top to bottom.
    case column(items: [Leaf])
}

/// Words or a button, at the deepest level.
enum Leaf {
    /// Words to read.
    case text(words: String)
    /// A button. Pressing it announces ButtonPressed with its label.
    case button(label: String)
}