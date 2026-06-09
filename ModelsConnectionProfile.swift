//
//  ConnectionProfile.swift
//  AI Translator
//
//  Модель профиля подключения к API
//

import Foundation

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

    /// Намеренно НЕ содержит apiToken, чтобы секрет не попадал в UserDefaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, apiUrl, modelName, temperature, maxTokens, icon
    }

    var isConfigured: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty && !modelName.isEmpty
    }
    
    var displayName: String {
        return "\(icon) \(name)"
    }
}
