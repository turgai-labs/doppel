actor Ann {
    private let maxRefundAmount: Double = 50
    private let approvedRefunds: [Int: Double] = [:] // Maps order number to approved amount

    func approveRefund(for order: Int, amount: Double) async throws -> ShopOrder {
        // Validate total amount
        if amount > maxRefundAmount {
            throw RefundError.tooLarge
        }

        // Simulate approval logic
        let approvedAmount = approvedRefunds[order] ?? 0
        let newAmount = max(0, amount - approvedAmount)

        return ShopOrder(
            number: order,
            item: "Item \(order)",
            amount: newAmount,
            status: .refunded
        )
    }

    // Private function to prevent external access
    private func validateRefund(for order: Int, amount: Double) async throws {
        if amount > maxRefundAmount {
            throw RefundError.tooLarge
        }
    }
}

enum RefundError: Error {
    case tooLarge
}
