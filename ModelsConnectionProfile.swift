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
    var apiToken: String
    var modelName: String
    var temperature: Double = 0.3
    var maxTokens: Int = 1024
    var icon: String = "🌐"
    
    var isConfigured: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty && !modelName.isEmpty
    }
    
    var displayName: String {
        return "\(icon) \(name)"
    }
}
