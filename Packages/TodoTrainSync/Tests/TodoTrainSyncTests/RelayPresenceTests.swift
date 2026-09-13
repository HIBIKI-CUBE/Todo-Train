import Testing
@testable import TodoTrainSync

@Suite("Relay presence")
struct RelayPresenceTests {
    @Test func anyIdleSignalIsIdle() {
        #expect(!RelayPresence().isIdle)
        #expect(RelayPresence(systemAsleep: true).isIdle)
        #expect(RelayPresence(screensAsleep: true).isIdle)
        #expect(RelayPresence(screensaver: true).isIdle)
        #expect(RelayPresence(systemAsleep: true, screensAsleep: true, screensaver: true).isIdle)
    }

    @Test func suppressesOnlyOnActiveToIdle() {
        #expect(RelayPresence.shouldSuppress(wasIdle: false, isIdle: true))
        #expect(!RelayPresence.shouldSuppress(wasIdle: true, isIdle: true))
        #expect(!RelayPresence.shouldSuppress(wasIdle: false, isIdle: false))
        #expect(!RelayPresence.shouldSuppress(wasIdle: true, isIdle: false))
    }

    @Test func resumesOnlyWhenLastIdleSignalClears() {
        #expect(RelayPresence.shouldResume(wasIdle: true, isIdle: false))
        #expect(!RelayPresence.shouldResume(wasIdle: false, isIdle: false))
        #expect(!RelayPresence.shouldResume(wasIdle: true, isIdle: true))
        #expect(!RelayPresence.shouldResume(wasIdle: false, isIdle: true))
    }

    @Test func screensaverStopWhileScreensAsleepStaysIdle() {
        let stillIdle = RelayPresence(screensAsleep: true, screensaver: false)
        #expect(stillIdle.isIdle)
        #expect(!RelayPresence.shouldResume(wasIdle: true, isIdle: stillIdle.isIdle))
    }
}
