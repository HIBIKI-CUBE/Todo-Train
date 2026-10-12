import Foundation

/// Build identity carried inside an encrypted snap, ack, or cmd.
/// Omitted entirely by older peers. `schema` is the store version string (`3.0.0`).
public struct WireBuildInfo: Codable, Equatable, Sendable {
    public var sha: String
    public var dirty: Bool
    public var schema: String
    public var builtAt: String

    public init(sha: String, dirty: Bool, schema: String, builtAt: String) {
        self.sha = sha
        self.dirty = dirty
        self.schema = schema
        self.builtAt = builtAt
    }

    /// A present `build` that is missing a field, or is not an object, is ignored.
    /// The surrounding snap, ack, or cmd still decodes.
    static func decodeLenient<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> WireBuildInfo? {
        guard container.contains(key) else { return nil }
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        return try? container.decode(WireBuildInfo.self, forKey: key)
    }
}

public enum PeerBuildStore {
    public static let defaultsKey = "companion.peerBuild"

    public static func load(from defaults: UserDefaults) -> WireBuildInfo? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WireBuildInfo.self, from: data)
    }

    public static func save(_ build: WireBuildInfo?, to defaults: UserDefaults) {
        guard let build, let data = try? JSONEncoder().encode(build) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}

public enum BuildInfoCopy {
    public static let title = "このビルド"
    public static let dirty = "未コミットの変更あり"
    public static let unrecorded = "記録なし"
    public static let explanation = "この iPhone に入っているアプリの作られた時点です。不具合を伝えるときや、Mac と組み合わせを確かめるときに使います。"
    public static let mismatch = "Mac のビルドが iPhone と違います。同じコミットから入れ直すと、連携の食い違いを避けられます。"
    public static let copied = "コピーしました"
}

public enum BuildStamp {
    public static let unknown = "unknown"

    /// `1047101 · develop · 10/12 16:20 · 版 3`、dirty のときは末尾に一言足す。
    public static func line(
        sha: String,
        branch: String,
        dirty: Bool,
        builtAt: String,
        schemaMajor: Int
    ) -> String {
        guard sha != unknown else { return BuildInfoCopy.unrecorded }
        let when = displayTime(builtAt) ?? builtAt
        var text = "\(sha) · \(branch) · \(when) · 版 \(schemaMajor)"
        if dirty {
            text += " · \(BuildInfoCopy.dirty)"
        }
        return text
    }

    public static func displayTime(_ iso: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: iso) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

public enum BuildMismatch {
    /// 両方の SHA が記録されていて違うときだけ、設定の Mac 欄に出す文。
    public static func notice(localSHA: String, peerSHA: String?) -> String? {
        guard let peerSHA,
              peerSHA != BuildStamp.unknown,
              localSHA != BuildStamp.unknown,
              peerSHA != localSHA
        else { return nil }
        return BuildInfoCopy.mismatch
    }
}
