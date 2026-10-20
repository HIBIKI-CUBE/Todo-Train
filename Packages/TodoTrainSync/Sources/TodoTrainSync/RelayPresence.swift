public struct RelayPresence: Equatable, Sendable {
    public var systemAsleep: Bool
    public var screensAsleep: Bool
    public var screensaver: Bool

    public init(systemAsleep: Bool = false, screensAsleep: Bool = false, screensaver: Bool = false) {
        self.systemAsleep = systemAsleep
        self.screensAsleep = screensAsleep
        self.screensaver = screensaver
    }

    public var isIdle: Bool { systemAsleep || screensAsleep || screensaver }

    /// Drop the socket only when we first become idle. Extra idle signals stay quiet.
    public static func shouldSuppress(wasIdle: Bool, isIdle: Bool) -> Bool {
        !wasIdle && isIdle
    }

    /// Reconnect immediately on the idle → active edge. Duplicate wake must not tear down a live socket.
    public static func shouldResume(wasIdle: Bool, isIdle: Bool) -> Bool {
        wasIdle && !isIdle
    }
}
