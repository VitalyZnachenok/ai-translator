//
//  LocalizationManager.swift
//  AI Translator
//
//  Управление языком интерфейса (системный / English / Русский).
//
//  Базовый язык проекта (CFBundleDevelopmentRegion) — английский, поэтому для
//  неподдерживаемых системных языков интерфейс автоматически откатывается на английский.
//  Русский — язык исходных строк (sourceLanguage в каталоге), английский — перевод.
//

import Foundation
import AppKit

/// Доступные варианты языка интерфейса.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ru

    var id: String { rawValue }

    /// Двухбуквенный код языка для конкретного варианта (для `.system` не применяется).
    var localeCode: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .ru: return "ru"
        }
    }
}

enum LocalizationManager {
    /// Ключ в UserDefaults, где хранится выбор пользователя.
    static let storageKey = "appLanguage"

    /// Системный ключ, которым переопределяется язык бандла.
    private static let appleLanguagesKey = "AppleLanguages"

    /// Языки, на которые переведён интерфейс.
    static let supportedCodes = ["en", "ru"]

    /// Текущий выбор пользователя.
    static var current: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    /// Применяет выбранный язык к `AppleLanguages`. Вызывать как можно раньше при старте,
    /// до построения UI, чтобы локализация бандла резолвилась в нужный язык.
    static func applyStartupLanguage() {
        let defaults = UserDefaults.standard
        if let code = current.localeCode {
            defaults.set([code], forKey: appleLanguagesKey)
        } else {
            // Системный режим: снимаем переопределение, чтобы язык выбирала ОС
            // (неподдерживаемые языки откатятся на developmentRegion = en).
            defaults.removeObject(forKey: appleLanguagesKey)
        }
    }

    /// Перезапускает приложение, чтобы применить новый язык интерфейса.
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
