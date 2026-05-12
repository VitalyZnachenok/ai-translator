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
    /// Значения от 0.0 до 1.0; ниже 0.3 обычно означает, что входной текст слишком короткий или смешанный.
    static let minimumConfidence: Double = 0.3

    /// Определяет наиболее вероятный язык переданного текста.
    /// Возвращает ISO-код языка (например, "ru", "en") или `nil`, если уверенность ниже порога.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage else { return nil }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominant] ?? 0
        guard confidence >= minimumConfidence else { return nil }

        return dominant.rawValue
    }
}
