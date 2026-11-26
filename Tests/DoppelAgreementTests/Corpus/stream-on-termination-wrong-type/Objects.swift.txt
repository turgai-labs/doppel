/// The user's calendars and their events.
actor Calendar {
    /// The calendars available in the user's account.
    func calendars() async throws -> [EventCalendar] {fatalError()}
}

/// The user's address book.
actor Contacts {
    /// Search names, email addresses, and phone numbers.
    func search(query: String) async throws -> [Contact] {fatalError()}
}

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

/// The user's reminders, as lists of reminders.
actor Reminders {
    /// Add a reminder, to the default list unless another is named.
    /// - Parameters:
    ///   - title: What to be reminded of.
    ///   - notes: More detail, if any.
    ///   - due: When it's due, if it has a due date.
    ///   - list: The list's name, such as "Groceries"; the default list if omitted.
    func add(title: String, notes: String?, due: String?, list: String?) async throws -> Reminder {fatalError()}
    /// The reminder lists, such as "Groceries" or "Work".
    func lists() async throws -> [ReminderList] {fatalError()}
}

/// A pretend shop, for trying out objects: orders come in and customers ask for refunds.
actor Shop {
    /// The managers on duty, who decide on refunds.
    var managers: [Object] { get async throws  {fatalError() }}
    /// The shop's orders, oldest first.
    var orders: [ShopOrder] { get async throws  {fatalError() }}
    /// A manager ends their shift: the refunds they hadn't decided go to another manager on duty, or wait for one.
    /// - Parameter manager: The manager, matched by identity.
    func endShift(manager: Object) async throws {fatalError()}
    /// Take an order.
    /// - Parameters:
    ///   - item: What was bought.
    ///   - amount: What it cost.
    func placeOrder(item: String, amount: Double) async throws -> ShopOrder {fatalError()}
    /// A manager approved a refund: it's paid out, and the customer is told.
    /// - Parameter order: The order's number.
    func refundApproved(order: Int) async throws -> ShopOrder {fatalError()}
    /// A manager refused a refund: the order stands, and the customer is told.
    /// - Parameter order: The order's number.
    func refundDenied(order: Int) async throws -> ShopOrder {fatalError()}
    /// A customer asks for their money back for an order. A manager on duty decides, and the shop returns without waiting for the decision.
    /// - Parameters:
    ///   - number: The order's number.
    ///   - replyTo: The customer, to tell how it ended: an object taking ``RefundCustomer``'s messages.
    func requestRefund(number: Int, replyTo: Object) async throws -> ShopOrder {fatalError()}
    /// A manager starts their shift: refund requests go to the managers on duty, in turn, starting with any that were waiting for one.
    /// - Parameter manager: The manager: the shop sends it refundRequested(order: Int, total: Double) for each refund it's to decide, and it answers the shop with refundApproved(order:) or refundDenied(order:).
    func startShift(manager: Object) async throws {fatalError()}
    func orderPlaced(order: ShopOrder) {fatalError()}
    func refundRequested(order: ShopOrder) {fatalError()}
}

/// A pretend warehouse, for trying out objects: it takes instructions about orders.
actor Warehouse {
    /// What the warehouse has been told, oldest first.
    var notes: [WarehouseNote] { get async throws  {fatalError() }}
    /// Tell the warehouse a refund was approved, so it expects the item back.
    /// - Parameter order: The refunded order.
    func refundApproved(order: ShopOrder) async throws {fatalError()}
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

struct EventCalendar {
    var id: [String: Any]
}

struct Contact {
    var id: [String: Any]
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

struct Reminder {
    var id: [String: Any]
}

struct ReminderList {
    var id: [String: Any]
}

/// An order in the shop.
struct ShopOrder {
    /// The order's number, counting from 1.
    var number: Int
    /// What was bought.
    var item: String
    /// What it cost.
    var amount: Double
    /// Where the order stands.
    var status: ShopOrderStatus
}

/// Where the order stands.
enum ShopOrderStatus: String {
    /// Bought and not disputed.
    case placed
    /// The customer asked for their money back.
    case refundRequested
    /// The money went back to the customer.
    case refunded
    /// The refund was refused; the order stands.
    case refundDenied
}

/// One instruction the warehouse received.
struct WarehouseNote {
    /// The order it's about.
    var order: Int
    /// The order's item.
    var item: String
    /// What to do.
    var instruction: WarehouseInstruction
    /// When it arrived.
    var at: String
}

/// What to do.
enum WarehouseInstruction: String {
    /// A refund was approved: the item is coming back.
    case expectReturn
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