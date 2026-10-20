//
//  FukeiSealGlyphs.swift
//  Todo train
//
//  字の描画はここだけ。字形を替えるときはこの中を直す。
//

import SwiftUI
import TodoTrainSync

enum FukeiSealGlyphs {
    static let fontName = "HiraMinProN-W6"

    static func draw(text: String, in rect: CGRect, context: inout GraphicsContext, color: Color) {
        guard rect.width > 0, rect.height > 0, !text.isEmpty else { return }
        let resolved = context.resolve(
            Text(text)
                .font(.custom(fontName, size: rect.height))
                .foregroundStyle(color)
        )
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}

enum FukeiSealDate {
    /// 時刻は入れない。東京の暦日。
    static func text(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = PunctualityJudgment.tokyoTimeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: date)
    }
}
