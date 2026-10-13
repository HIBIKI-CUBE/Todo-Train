enum TimetablePauseDispatching {
    /// A timetable time does not send pause. The arguments stay so a caller
    /// cannot treat `now >= pauseAt` as a reason to stop the ride.
    static func shouldSend(
        now: Int,
        pauseAt: Int?,
        alreadySent: Int?,
        canPause: Bool,
        isSending: Bool
    ) -> Bool {
        _ = (now, pauseAt, alreadySent, canPause, isSending)
        return false
    }
}
