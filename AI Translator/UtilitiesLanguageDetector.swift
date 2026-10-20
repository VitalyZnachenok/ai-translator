//
//  LanguageDetector.swift
//  AI Translator
//
//  Локальное определение языка через Apple Natural Language framework.
//

import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// Минимальная уверенность модели, чтобы считать определение надёжным.
    static let minimumConfidence: Double = 0.3

    /// Уверенность, при которой результат принимается без оглядки на предпочитаемые языки.
    static let confidentThreshold: Double = 0.9

    /// Коды языков, которые знает приложение (без "auto").
    static let supportedCodes: [String] = LanguageData.languages
        .map(\.code)
        .filter { $0 != "auto" }

    /// Определяет наиболее вероятный язык переданного текста.
    ///
    /// Двухступенчатая схема, потому что на коротких фразах NLLanguageRecognizer
    /// ошибается именно в ту сторону, которая ломает авто-обмен: «Привет» → bg,
    /// «Hi» → tr, «ok» → pl, «да» → uk.
    ///
    /// 1. Распознавание среди всех поддерживаемых языков. Уверенный ответ
    ///    (≥ `confidentThreshold`) принимается как есть — немецкая фраза
    ///    остаётся немецкой, даже если в парах только ru/en.
    /// 2. Неуверенный ответ пересчитывается только среди `preferred`
    ///    (языки активных пар, выбранная цель и т.п.): короткое «Hi» становится
    ///    en, а «да» — ru.
    /// 3. Если и это не помогло — эвристика по алфавиту (кириллица, латиница,
    ///    иероглифы, кана, хангыль, арабица, деванагари).
    ///
    /// - Parameters:
    ///   - text: текст для определения.
    ///   - preferred: коды языков, которые ожидает пользователь; порядок задаёт приоритет.
    ///   - candidates: если задано, распознавание ограничено этими кодами (например,
    ///     `[source, target]` при проверке результата перевода).
    ///   - minimumConfidence: порог для принятия результата.
    /// - Returns: код языка в нотации приложения ("ru", "en", "zh", …) или `nil`.
    static func detect(
        _ text: String,
        preferring preferred: [String] = [],
        among candidates: [String]? = nil,
        minimumConfidence: Double = minimumConfidence
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let universe = candidates ?? supportedCodes
        let preferredInUniverse = preferred.filter { universe.contains($0) }

        // Ступень 1: среди всех кандидатов.
        if let (code, confidence) = recognize(trimmed, constrainedTo: universe) {
            if confidence >= confidentThreshold || preferredInUniverse.isEmpty {
                return confidence >= minimumConfidence ? code : scriptFallback(trimmed, preferred: preferredInUniverse, candidates: universe)
            }
            if preferredInUniverse.contains(code), confidence >= minimumConfidence {
                return code
            }
        }

        // Ступень 2: только среди предпочитаемых языков.
        if !preferredInUniverse.isEmpty,
           let (code, confidence) = recognize(trimmed, constrainedTo: preferredInUniverse),
           confidence >= 0.5 {
            return code
        }

        // Ступень 3: по алфавиту.
        return scriptFallback(trimmed, preferred: preferredInUniverse, candidates: universe)
    }

    // MARK: - NaturalLanguage

    private static func recognize(_ text: String, constrainedTo codes: [String]) -> (String, Double)? {
        let recognizer = NLLanguageRecognizer()
        let constraints = codes.flatMap(nlLanguages(for:))
        if !constraints.isEmpty {
            recognizer.languageConstraints = constraints
        }
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        guard let code = appCode(for: best.key), codes.contains(code) else { return nil }
        return (code, best.value)
    }

    /// Коды приложения → языки NaturalLanguage. Китайский представлен двумя письменностями.
    private static func nlLanguages(for code: String) -> [NLLanguage] {
        switch code {
        case "zh": return [.simplifiedChinese, .traditionalChinese]
        default: return [NLLanguage(rawValue: code)]
        }
    }

    /// Обратное отображение: "zh-Hans"/"zh-Hant" → "zh", остальные — как есть.
    private static func appCode(for language: NLLanguage) -> String? {
        switch language {
        case .simplifiedChinese, .traditionalChinese: return "zh"
        default: return language.rawValue
        }
    }

    // MARK: - Script heuristic

    private static let scriptLanguages: [(range: ClosedRange<UInt32>, codes: [String])] = [
        (0x0400...0x052F, ["ru", "uk"]),
        (0x0041...0x024F, ["en", "es", "fr", "de", "it", "pt", "tr", "pl"]),
        (0x3040...0x30FF, ["ja"]),
        (0xAC00...0xD7AF, ["ko"]),
        (0x4E00...0x9FFF, ["zh", "ja"]),
        (0x3400...0x4DBF, ["zh"]),
        (0x0600...0x06FF, ["ar"]),
        (0x0900...0x097F, ["hi"]),
    ]

    private static func scriptFallback(_ text: String, preferred: [String], candidates: [String]) -> String? {
        var counts = [Int](repeating: 0, count: scriptLanguages.count)
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            for (index, entry) in scriptLanguages.enumerated() where entry.range.contains(scalar.value) {
                counts[index] += 1
                break
            }
        }
        guard let bestIndex = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[bestIndex] > 0 else {
            return nil
        }
        let codes = scriptLanguages[bestIndex].codes.filter { candidates.contains($0) }
        if let hit = preferred.first(where: { codes.contains($0) }) {
            return hit
        }
        return codes.first
    }
}
