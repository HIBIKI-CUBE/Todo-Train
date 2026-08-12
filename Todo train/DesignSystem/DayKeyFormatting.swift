//
//  DayKeyFormatting.swift
//  Todo train
//

import Foundation

enum DayKeyFormatting {
    /// Formats `yyyy-MM-dd` day keys for UI (e.g. `8月12日（水）`).
    static func displayDay(from dayKey: String, locale: Locale = Locale(identifier: "ja_JP")) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日（E）"
        return formatter.string(from: date)
    }
}
