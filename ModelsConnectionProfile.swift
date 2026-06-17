//
//  ConnectionProfile.swift
//  AI Translator
//
//  Модель профиля подключения к API
//

import Foundation

/// Управление «мышлением» (reasoning) у думающих моделей.
/// Для Ollama через OpenAI-совместимый `/v1/chat/completions` отображается в поле
/// `reasoning_effort` ("none" — выключить, "low"/"medium"/"high" — уровень).
enum ReasoningEffort: String, Codable, CaseIterable, Identifiable {
    /// Не отправлять параметр — поведение сервера/модели по умолчанию.
    case serverDefault
    /// Полностью отключить мышление.
    case off
    case low
    case medium
    case high

    var id: String { rawValue }

    /// Значение для поля `reasoning_effort`. `nil` — параметр не отправляется.
    var apiValue: String? {
        switch self {
        case .serverDefault: return nil
        case .off: return "none"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    var displayName: String {
        switch self {
        case .serverDefault: return String(localized: "По умолчанию")
        case .off: return String(localized: "Выключено")
        case .low: return String(localized: "Низкое")
        case .medium: return String(localized: "Среднее")
        case .high: return String(localized: "Высокое")
        }
    }
}

struct ConnectionProfile: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var apiUrl: String
    /// API-токен. Не сериализуется в UserDefaults — хранится в Keychain (см. SettingsManager/KeychainHelper).
    var apiToken: String = ""
    var modelName: String
    var temperature: Double = 0.3
    var maxTokens: Int = 2048
    var icon: String = "🌐"
    /// Управление мышлением думающих моделей (см. ReasoningEffort).
    var reasoningEffort: ReasoningEffort = .serverDefault

    /// Намеренно НЕ содержит apiToken, чтобы секрет не попадал в UserDefaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, apiUrl, modelName, temperature, maxTokens, icon, reasoningEffort
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        apiUrl: String,
        apiToken: String = "",
        modelName: String,
        temperature: Double = 0.3,
        maxTokens: Int = 2048,
        icon: String = "🌐",
        reasoningEffort: ReasoningEffort = .serverDefault
    ) {
        self.id = id
        self.name = name
        self.apiUrl = apiUrl
        self.apiToken = apiToken
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.icon = icon
        self.reasoningEffort = reasoningEffort
    }

    // Кастомное декодирование: новые/отсутствующие поля получают значения по умолчанию,
    // чтобы профили из старых версий читались без ошибок.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        apiUrl = try c.decodeIfPresent(String.self, forKey: .apiUrl) ?? ""
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "🌐"
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .serverDefault
        // apiToken восстанавливается отдельно из Keychain.
    }

    var isConfigured: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty && !modelName.isEmpty
    }
    
    var displayName: String {
        return "\(icon) \(name)"
    }
}
