import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func syncCabinNotification() {
        cabinNotifier.sync(interrupt: cabinInterrupt)
    }

    var optimisticFiredCount: Int {
        guard let sessionId = snap?.sessionId,
              defaults.string(forKey: Defaults.cabinOptimisticSession) == sessionId.uuidString.lowercased() else {
            return 0
        }
        return defaults.integer(forKey: Defaults.cabinOptimisticFired)
    }

    func markOptimisticCabin(sessionId: UUID, firedCount: Int) {
        defaults.set(sessionId.uuidString.lowercased(), forKey: Defaults.cabinOptimisticSession)
        defaults.set(firedCount, forKey: Defaults.cabinOptimisticFired)
    }

    func clearOptimisticCabin() {
        defaults.removeObject(forKey: Defaults.cabinOptimisticSession)
        defaults.removeObject(forKey: Defaults.cabinOptimisticFired)
    }

    func reconcileOptimisticCabin() {
        guard let snap else {
            clearOptimisticCabin()
            return
        }
        let stored = defaults.string(forKey: Defaults.cabinOptimisticSession)
        if stored != snap.sessionId?.uuidString.lowercased() {
            clearOptimisticCabin()
            return
        }
        if snap.checkInFiredCount >= defaults.integer(forKey: Defaults.cabinOptimisticFired) {
            clearOptimisticCabin()
        }
    }
}
