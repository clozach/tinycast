import Foundation

enum WindowSwitchEligibility {
    static func includes(isStandard: Bool, isDialog: Bool, canMinimize: Bool) -> Bool {
        isStandard || (isDialog && canMinimize)
    }
}
