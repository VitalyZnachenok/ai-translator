//
//  TranslationDirection.swift
//  AI Translator
//
//  Выбор направления перевода: локальное определение исходного языка и защита
//  от запроса «переведи с русского на русский», который модель может выполнить
//  только перефразированием.
//

import Foundation

struct ResolvedDirection: Equatable {
    /// Исходный язык, отправляемый модели. "auto" остаётся только если определить не удалось.
    var source: String
    /// Целевой язык после всех корректировок.
    var target: String
    /// Что определил локальный детектор (nil — не определил или источник был задан явно).
    var detected: String?
    /// Целевой язык был заменён, потому что совпал с исходным.
    var targetChanged: Bool

    var label: String { "\(source)→\(target)" }
}

enum TranslationDirectionResolver {
    /// Определяет фактическое направление перевода для текста.
    ///
    /// - Parameters:
    ///   - text: переводимый текст.
    ///   - requestedSource: язык, выбранный пользователем, или "auto".
    ///   - requestedTarget: целевой язык, выбранный пользователем.
    ///   - pairs: языковые пары (используются как подсказка детектору и как
    ///     источник «другого» языка, если цель совпала с исходным).
    ///   - fallbackSource: язык, который считать целью при совпадении, если пары
    ///     не помогли (обычно последний явно выбранный исходный язык).
    static func resolve(
        text: String,
        requestedSource: String,
        requestedTarget: String,
        pairs: [LanguagePair],
        fallbackSource: String? = nil
    ) -> ResolvedDirection {
        var preferred: [String] = []
        for pair in pairs where pair.enabled {
            preferred.append(pair.primary)
            preferred.append(pair.secondary)
        }
        preferred.append(requestedTarget)
        if requestedSource != "auto" { preferred.append(requestedSource) }
        if let fallbackSource, fallbackSource != "auto" { preferred.append(fallbackSource) }

        var source = requestedSource
        var detected: String?
        if source == "auto" {
            detected = LanguageDetector.detect(text, preferring: preferred)
            if let detected { source = detected }
        }

        var target = requestedTarget
        var changed = false
        if source != "auto", source == target {
            target = alternativeTarget(for: source, pairs: pairs, fallbackSource: fallbackSource)
            changed = true
        }

        return ResolvedDirection(source: source, target: target, detected: detected, targetChanged: changed)
    }

    /// Куда переводить текст на языке `language`, если пользователь выбрал его же целью.
    static func alternativeTarget(for language: String, pairs: [LanguagePair], fallbackSource: String?) -> String {
        for pair in pairs where pair.enabled {
            if let other = pair.target(for: language) { return other }
        }
        if let fallbackSource, fallbackSource != "auto", fallbackSource != language {
            return fallbackSource
        }
        return language == "en" ? "ru" : "en"
    }
}
