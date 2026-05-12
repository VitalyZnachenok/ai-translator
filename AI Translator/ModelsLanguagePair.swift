//
//  LanguagePair.swift
//  AI Translator
//
//  Двунаправленная пара языков для in-place перевода с автоопределением направления.
//

import Foundation

struct LanguagePair: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    /// Первый язык пары (код, например "ru").
    var primary: String
    /// Второй язык пары (код, например "en").
    var secondary: String
    /// Учитывается ли пара при автоматическом подборе направления.
    var enabled: Bool = true

    init(id: String = UUID().uuidString, primary: String, secondary: String, enabled: Bool = true) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.enabled = enabled
    }

    /// Возвращает целевой язык для перевода, если входной язык совпадает с одним из языков пары.
    /// Возвращает `nil`, если язык не относится к этой паре или пара отключена.
    func target(for detectedLanguage: String) -> String? {
        guard enabled else { return nil }
        if detectedLanguage == primary { return secondary }
        if detectedLanguage == secondary { return primary }
        return nil
    }
}
