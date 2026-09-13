import Foundation

enum MacComputerName {
    static func current() -> String {
        let raw = Host.current().localizedName ?? Host.current().name ?? "Mac"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mac" : trimmed
    }
}
