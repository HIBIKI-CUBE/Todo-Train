import Foundation

/// Printed occupancy on the 60-minute Mars track. Hub maps timetable marks into this.
public struct MarsOccupancyMark: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 0...1 along the 60-minute rail.
    public var position: Double
    /// Remaining occupancy as a band from `position`.
    public var span: Double
    public var isCurrent: Bool
    public var isAdopted: Bool

    public init(id: UUID, position: Double, span: Double, isCurrent: Bool, isAdopted: Bool) {
        self.id = id
        self.position = position
        self.span = span
        self.isCurrent = isCurrent
        self.isAdopted = isAdopted
    }
}
