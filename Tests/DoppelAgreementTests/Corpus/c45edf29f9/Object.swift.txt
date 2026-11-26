actor PressCounter {
    private var count = 0
    
    func countButtonPresses(label: String) {
        buttonPressEvents?.buttonPressed(label: label)
        count += 1
    }
}

// Use with the website:
// let counter = PressCounter()
// counter.buttonPresses = website
// counter.countButtonPresses(label: "Submit")
