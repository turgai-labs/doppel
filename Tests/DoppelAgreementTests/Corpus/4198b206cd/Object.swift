```swift
actor Bob {
    var data: [String: Int] = [:]
    
    func startShift(manager: String) -> String {
        return "Shift started with manager: \(manager)"
    }
    
    func placeOrder(item: String, amount: Int) -> String {
        return "Order placed for \(item), amount: \(amount)"
    }
    
    func refundApproved(order: String) -> String {
        if let amount = data[order], amount <= 20 {
            return "Refund approved for order \(order) with amount \(amount)"
        } else {
            return "Refund denied for order \(order): amount exceeds 20"
        }
    }
    
    func refundDenied(order: String) -> String {
        return "Refund denied for order \(order)"
    }
    
    func requestRefund(number: String, replyTo: String) -> String {
        return "Refund request sent for number \(number) to replyTo: \(replyTo)"
    }
}

// Value named after Bob
struct Bob {
    func startShift(manager: String) -> String {
        return "Bob's shift started with manager: \(manager)"
    }
    
    func placeOrder(item: String, amount: Int) -> String {
        return "Bob ordered \(item), amount: \(amount)"
    }