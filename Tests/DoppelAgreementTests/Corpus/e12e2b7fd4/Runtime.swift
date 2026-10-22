/// Another object, of a type this code doesn't declare: what's called on it is a message.
typealias Object = any Actor

/// An object reached by a name whose type isn't declared.
actor Undeclared {}

/// What an `@Event` function's body calls: the event, announced with its values.
func __announce(_ event: String, _ values: [String: any Sendable]) {}

// The objects the code reaches by name.
let mac = Mac()
let mediaControl = MediaControl()
let website = Website()
