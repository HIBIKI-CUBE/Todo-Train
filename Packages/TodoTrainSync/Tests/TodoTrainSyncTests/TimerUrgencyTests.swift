import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Timer urgency")
struct TimerUrgencyTests {
    @Test func fiveMinuteTicketThresholds() {
        let budget: TimeInterval = 5 * 60
        #expect(TimerUrgency.phase(remaining: 300, budgetSeconds: budget) == .cruise)
        #expect(TimerUrgency.phase(remaining: 91, budgetSeconds: budget) == .cruise)
        #expect(TimerUrgency.phase(remaining: 90, budgetSeconds: budget) == .approach)
        #expect(TimerUrgency.phase(remaining: 31, budgetSeconds: budget) == .approach)
        #expect(TimerUrgency.phase(remaining: 30, budgetSeconds: budget) == .final)
        #expect(TimerUrgency.phase(remaining: -1, budgetSeconds: budget) == .overtime)
    }

    @Test func clockFormatsAbsoluteMinutes() {
        #expect(ClockTime.mmss(1380) == "23:00")
        #expect(ClockTime.mmss(-65) == "1:05")
        #expect(MenuBarPresentation.formatRemaining(-65) == "+1:05")
    }
}

@Suite("HTTP transport URL")
struct URLSessionHTTPTransportTests {
    @Test func replacesPathInsteadOfAppending() throws {
        let base = try #require(URL(string: "https://todo-train.hibiki-cube.dev"))
        let url = try URLSessionHTTPTransport.resourceURL(baseURL: base, path: "/v1/offers/abc/bind")
        #expect(url.absoluteString == "https://todo-train.hibiki-cube.dev/v1/offers/abc/bind")
    }

    @Test func stripsQueryAndFragmentFromBase() throws {
        let base = try #require(URL(string: "https://example.test/ignored?x=1#frag"))
        let url = try URLSessionHTTPTransport.resourceURL(baseURL: base, path: "/v1/snap")
        #expect(url.absoluteString == "https://example.test/v1/snap")
    }
}

@Suite("Remote apply gate")
struct RemotePauseApplyGateTests {
    @Test func onlyApplyMutatesSession() {
        #expect(RemotePauseDecision.apply.shouldApply)
        #expect(!RemotePauseDecision.pauseLimitReached.shouldApply)
        #expect(!RemotePauseDecision.sessionMismatch.shouldApply)
        #expect(!RemotePauseDecision.noActiveService.shouldApply)
        #expect(!RemotePauseDecision.notPaused.shouldApply)
    }
}
