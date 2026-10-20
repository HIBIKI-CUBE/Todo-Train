// LLM 側のコーパス: Apple の英語原文を、オンデバイスモデルに日本語 UI 文言として書かせる。
// 入力: JSON Lines（id, en）を stdin。出力: JSON Lines（id, ja）を stdout。
// swift tools/wording/llm_baseline.swift < sample.jsonl > llm.jsonl
import FoundationModels
import Foundation

struct Item: Codable { let id: Int; let en: String }
struct Out: Codable { let id: Int; let ja: String }

let instructions = """
あなたは iPhone アプリの日本語 UI 文言を書く。与えられた英語の UI 文言と同じ役割の日本語を 1 つだけ出力する。
説明・引用符・前置きは付けない。◯ はプレースホルダなのでそのまま残す。
"""

let encoder = JSONEncoder()
while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let item = try? JSONDecoder().decode(Item.self, from: data) else { continue }
    let session = LanguageModelSession(instructions: instructions)
    do {
        let r = try await session.respond(to: item.en)
        let ja = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = try? encoder.encode(Out(id: item.id, ja: ja)),
           let s = String(data: json, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    } catch {
        FileHandle.standardError.write("skip \(item.id): \(error)\n".data(using: .utf8)!)
    }
}
