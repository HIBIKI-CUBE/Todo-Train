import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Build stamp")
struct BuildStampTests {
    @Test func lineUsesJSTAndSchemaMajor() {
        let line = BuildStamp.line(
            sha: "1047101",
            branch: "develop",
            dirty: false,
            builtAt: "2026-10-12T16:20:00+09:00",
            schemaMajor: 3
        )
        #expect(line == "1047101 · develop · 10/12 16:20 · 版 3")
    }

    @Test func dirtyAppendsOnePhrase() {
        let line = BuildStamp.line(
            sha: "1047101",
            branch: "develop",
            dirty: true,
            builtAt: "2026-10-12T16:20:00+09:00",
            schemaMajor: 4
        )
        #expect(line == "1047101 · develop · 10/12 16:20 · 版 4 · 未コミットの変更あり")
    }

    @Test func unknownSHAIsUnrecorded() {
        let line = BuildStamp.line(
            sha: "unknown",
            branch: "unknown",
            dirty: false,
            builtAt: "unknown",
            schemaMajor: 3
        )
        #expect(line == "記録なし")
    }

    @Test func mismatchOnlyWhenBothSHAsDiffer() {
        #expect(BuildMismatch.notice(localSHA: "aaaaaaa", peerSHA: "bbbbbbb") == BuildInfoCopy.mismatch)
        #expect(BuildMismatch.notice(localSHA: "aaaaaaa", peerSHA: "aaaaaaa") == nil)
        #expect(BuildMismatch.notice(localSHA: "aaaaaaa", peerSHA: nil) == nil)
        #expect(BuildMismatch.notice(localSHA: "aaaaaaa", peerSHA: "unknown") == nil)
        #expect(BuildMismatch.notice(localSHA: "unknown", peerSHA: "bbbbbbb") == nil)
    }
}
