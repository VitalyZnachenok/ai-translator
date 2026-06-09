//
//  LanguageData.swift
//  AI Translator
//
//  Список поддерживаемых языков
//

import Foundation

struct LanguageData {
    /// Единый источник: (код, полное название, компактное название).
    static let languages: [(code: String, full: String, compact: String)] = [
        ("auto", "🌐 Авто-определение", "🌐 Авто"),
        ("en", "🇺🇸 English", "🇺🇸 EN"),
        ("ru", "🇷🇺 Русский", "🇷🇺 RU"),
        ("zh", "🇨🇳 中文", "🇨🇳 ZH"),
        ("es", "🇪🇸 Español", "🇪🇸 ES"),
        ("fr", "🇫🇷 Français", "🇫🇷 FR"),
        ("de", "🇩🇪 Deutsch", "🇩🇪 DE"),
        ("ja", "🇯🇵 日本語", "🇯🇵 JA"),
        ("ko", "🇰🇷 한국어", "🇰🇷 KO"),
        ("it", "🇮🇹 Italiano", "🇮🇹 IT"),
        ("pt", "🇵🇹 Português", "🇵🇹 PT"),
        ("ar", "🇸🇦 العربية", "🇸🇦 AR"),
        ("hi", "🇮🇳 हिन्दी", "🇮🇳 HI"),
        ("tr", "🇹🇷 Türkçe", "🇹🇷 TR"),
        ("uk", "🇺🇦 Українська", "🇺🇦 UA"),
        ("pl", "🇵🇱 Polski", "🇵🇱 PL")
    ]

    static let fullLanguages: [(String, String)] = languages.map { ($0.code, $0.full) }

    static let compactLanguages: [(String, String)] = languages.map { ($0.code, $0.compact) }

    /// Возвращает полное отображаемое имя по коду языка (или сам код, если не найден).
    static func displayName(for code: String) -> String {
        languages.first { $0.code == code }?.full ?? code
    }
}
