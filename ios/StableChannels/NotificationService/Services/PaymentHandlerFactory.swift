import Foundation

enum PaymentHandlerResult {
    case success
    case pending
    case failure
}

protocol PaymentHandler {
    var direction: PaymentDirection { get }
    func handle(
        node: LDKNode.Node,
        db: PaymentDatabase,
        priceFetcher: PriceFetcher,
        baseContent: UNMutableNotificationContent,
        mutator: NotificationContentMutator,
        completion: @escaping (UNMutableNotificationContent, Bool?) -> Void
    )
}

enum PaymentHandlerFactory {
    static let logger = FileLogger(appGroup: Constants.appGroup)

    static func handler(for direction: PaymentDirection) -> PaymentHandler {
        switch direction {
        case .lspToUser: return LSPToUserHandler()
        case .userToLsp: return UserToLSPHandler()
        case .incomingPayment: return IncomingPaymentHandler()
        }
    }
}
