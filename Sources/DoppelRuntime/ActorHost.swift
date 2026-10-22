/// What running a file needs from outside it: everything the files it's given declare. Their
/// actors are other objects, called and read by message; their functions are the host's own,
/// and their constants run here, as Swift runs them. The host is asked on the executor the code runs on.
public protocol ActorHost: AnyObject {
    /// The actor whose code runs, as other objects are given it.
    var itself: ObjectHandle { get }
    /// A message to another object: its method, with its arguments and their labels, sent through
    /// the type the code holds the object as: a declared actor type, which the object refuses
    /// being sent through if it isn't one, as a call through a type runs only on that type; a
    /// protocol, `any Shop.RefundManager`, which any object taking the message conforms to; or
    /// `nil` for any object (`Object`).
    func send(
        _ message: String, to object: ObjectHandle, through type: String?,
        arguments: [(label: String?, value: Portable)]
    ) async throws -> Portable
    /// What another object publishes.
    func read(_ property: String, of object: ObjectHandle) async throws -> Portable
    /// An actor a given file declares, made with the arguments its initializer was called with,
    /// each with its label: the object that makes.
    func make(_ type: String, arguments: [(label: String?, value: Portable)]) async throws -> ObjectHandle
    /// A function a given file declares, called.
    func call(_ function: String, arguments: [(label: String?, value: Portable)]) async throws -> Portable
    /// A `Task { … }` the code started, which the host runs with ``LiveActor/runTask(_:)``.
    func schedule(task id: Int)
    func cancel(task id: Int)
    /// What the code printed.
    func print(_ text: String)
}
