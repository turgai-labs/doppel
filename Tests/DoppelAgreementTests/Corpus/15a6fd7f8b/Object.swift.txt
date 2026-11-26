```swift
actor Bob {
    // What Bob keeps: his pay, starting at 3000.
    private(set) var pay = 3000

    // Ann, reached by name. Her events call Bob's functions of the same name.
    
    private let ann = Ann()

    // What Bob can be asked to do: ask Ann for a raise of the given amount.
    func askForRaise(amount: Int) async throws {
        try await ann.requestRaise(amount: amount)
336:- `pay`, the `@Subscribed` ann reference, and the `async throws` signature are unchanged; if `requestRaise` throws, the error propagates and pay is still untouched.
386:- `pay`, the `@Subscribed` ann reference, and the `async throws` signature are unchanged; if `requestRaise` throws, the error propagates and pay is still untouched.
548:2026-10-15T12:05:25+0200 info eval: action=askForRaise arguments={"amount":200} cluster/node=sact://eval@127.0.0.1:59632 error=line 16: condition must be Bool, got Optional handle=bob [TurgaiApplication] Object call failed
555:The change: Fix the compile error in askForRaise(amount:): the condition must be a Bool, not an Optional. Unwrap the Bool returned by Ann's requestRaise(amount:) — e.g. `if let approved = ann.requestRaise(amount: amount), approved { pay += amount }` or for
654:The refusal is about the `if let` form: the checker resolves the names in the condition against what the function already knows — `amount`, `ann`, `pay` — and doesn't carry the `if let` binding into the trailing clause, so `approved` there is unknown. The 
694:- `approved` is a function-level `let`, which the checker already resolves fine in a plain `if` condition — the original failure was "condition must be Bool, got Optional", not an unknown-name error.
695:- `approved == true` is a `Bool` expression (`Optional` compares equal when the wrapped value matches), so the condition-type error is gone. No `if let` binding is involved, so there's no name-visibility issue either.
729:FAIL  322s  Make a manager, Ann, with a budget of 1000. W  (turn 2: modelMisbehavior("decoding error: Exceeded maximum tool iterations (8) while processing Ollama tool calls."))
930:2026-10-15T12:07:46+0200 warning eval: cluster/node=sact://eval@127.0.0.1:59787 error=notRunning event=approved object=74bf653d-6ff1-4b59-b857-0266e500f6c7 [TurgaiObjects] A dynamic object's subscription ended
947:2026-10-15T12:07:47+0200 warning eval: cluster/node=sact://eval@127.0.0.1:59787 error=notRunning event=denied object=74bf653d-6ff1-4b59-b857-0266e500f6c7 [TurgaiObjects] A dynamic object's subscription ended