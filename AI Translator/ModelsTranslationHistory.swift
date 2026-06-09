//
//  TranslationHistory.swift
//  AI Translator
//
//  Модель и хранилище истории переводов.
//

import Foundation
import Observation

struct TranslationHistoryEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var sourceText: String
    var translatedText: String
    var sourceLanguage: String
    var targetLanguage: String
    /// Откуда инициирован перевод (для информации в UI).
    var origin: String
}

@Observable
final class TranslationHistoryStore {
    static let shared = TranslationHistoryStore()

    private(set) var entries: [TranslationHistoryEntry] = []

    /// Максимальное число хранимых записей.
    private let maxEntries = 100
    private let storageKey = "translationHistory"
    private let userDefaults = UserDefaults.standard

    private init() {
        load()
    }

    func add(
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        origin: String
    ) {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResult = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedResult.isEmpty else { return }

        let entry = TranslationHistoryEntry(
            sourceText: trimmedSource,
            translatedText: trimmedResult,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            origin: origin
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(_ entry: TranslationHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
