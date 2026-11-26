actor PressCounter {
    private var count = 0
    
     var buttonPressEvents = WebsiteEvents()
    
    func countButtonPresses(label: String) {
        buttonPressEvents?.buttonPressed(label: label)
        count += 1
    }
}
