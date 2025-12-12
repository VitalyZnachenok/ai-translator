//
//  SettingsManager.swift
//  AI Translator
//
//  Менеджер для управления настройками и профилями
//

import Foundation
import SwiftUI
import Observation

@Observable
final class SettingsManager {
    // MARK: - Properties
    
    var connectionProfiles: [ConnectionProfile] = []
    var activeProfileId: String = ""
    var customPrompts: [TranslationPrompt] = []
    var quickTranslateHotkey: String = "⌘⇧T"
    
    // MARK: - Computed Properties
    
    var apiUrl: String {
        get { activeProfile?.apiUrl ?? "" }
        set {
            guard var profile = activeProfile else { return }
            profile.apiUrl = newValue
            updateActiveProfile(profile)
        }
    }
    
    var apiToken: String {
        get { activeProfile?.apiToken ?? "" }
        set {
            guard var profile = activeProfile else { return }
            profile.apiToken = newValue
            updateActiveProfile(profile)
        }
    }
    
    var modelName: String {
        get { activeProfile?.modelName ?? "" }
        set {
            guard var profile = activeProfile else { return }
            profile.modelName = newValue
            updateActiveProfile(profile)
        }
    }
    
    var temperature: Double {
        get { activeProfile?.temperature ?? 0.3 }
        set {
            guard var profile = activeProfile else { return }
            profile.temperature = newValue
            updateActiveProfile(profile)
        }
    }
    
    var maxTokens: Int {
        get { activeProfile?.maxTokens ?? 1024 }
        set {
            guard var profile = activeProfile else { return }
            profile.maxTokens = newValue
            updateActiveProfile(profile)
        }
    }
    
    var isConfigured: Bool {
        activeProfile?.isConfigured ?? false
    }
    
    var activeProfile: ConnectionProfile? {
        get { connectionProfiles.first { $0.id == activeProfileId } }
        set {
            if let newProfile = newValue {
                updateActiveProfile(newProfile)
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Initialization
    
    init() {
        loadSettings()
        migrateOldSettings()
    }
    
    // MARK: - Public Methods
    
    func loadSettings() {
        if let profilesData = userDefaults.data(forKey: "connectionProfiles"),
           let decodedProfiles = try? JSONDecoder().decode([ConnectionProfile].self, from: profilesData) {
            connectionProfiles = decodedProfiles
        }
        
        activeProfileId = userDefaults.string(forKey: "activeProfileId") ?? ""
        
        if activeProfileId.isEmpty, let firstProfile = connectionProfiles.first {
            activeProfileId = firstProfile.id
        }
        
        if let promptsData = userDefaults.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([TranslationPrompt].self, from: promptsData) {
            customPrompts = decodedPrompts
        }
        
        quickTranslateHotkey = userDefaults.string(forKey: "quickTranslateHotkey") ?? "⌘⇧T"
    }
    
    func saveSettings() {
        if let encodedProfiles = try? JSONEncoder().encode(connectionProfiles) {
            userDefaults.set(encodedProfiles, forKey: "connectionProfiles")
        }
        
        userDefaults.set(activeProfileId, forKey: "activeProfileId")
        
        if let encodedPrompts = try? JSONEncoder().encode(customPrompts) {
            userDefaults.set(encodedPrompts, forKey: "customPrompts")
        }
        
        userDefaults.set(quickTranslateHotkey, forKey: "quickTranslateHotkey")
    }
    
    // MARK: - Profile Management
    
    func addProfile(_ profile: ConnectionProfile) {
        connectionProfiles.append(profile)
        saveSettings()
    }
    
    func updateProfile(_ profile: ConnectionProfile) {
        if let index = connectionProfiles.firstIndex(where: { $0.id == profile.id }) {
            connectionProfiles[index] = profile
            saveSettings()
        }
    }
    
    func deleteProfile(_ profile: ConnectionProfile) {
        connectionProfiles.removeAll { $0.id == profile.id }
        
        if activeProfileId == profile.id {
            activeProfileId = connectionProfiles.first?.id ?? ""
        }
        
        saveSettings()
    }
    
    func setActiveProfile(_ profileId: String) {
        guard connectionProfiles.contains(where: { $0.id == profileId }) else { return }
        activeProfileId = profileId
        saveSettings()
    }
    
    func duplicateProfile(_ profile: ConnectionProfile) -> ConnectionProfile {
        let newProfile = ConnectionProfile(
            name: "\(profile.name) (Копия)",
            apiUrl: profile.apiUrl,
            apiToken: profile.apiToken,
            modelName: profile.modelName,
            temperature: profile.temperature,
            maxTokens: profile.maxTokens,
            icon: profile.icon
        )
        addProfile(newProfile)
        return newProfile
    }
    
    func resetToDefaults() {
        connectionProfiles = []
        activeProfileId = ""
        customPrompts = []
        quickTranslateHotkey = "⌘⇧T"
        saveSettings()
    }
    
    func createExampleProfiles() -> [ConnectionProfile] {
        [
            ConnectionProfile(
                name: "OpenAI GPT-4",
                apiUrl: "https://api.openai.com/v1",
                apiToken: "",
                modelName: "gpt-4o-mini",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🤖"
            ),
            ConnectionProfile(
                name: "Локальный Ollama",
                apiUrl: "http://localhost:11434/v1",
                apiToken: "ollama",
                modelName: "llama3.2:latest",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🦙"
            ),
            ConnectionProfile(
                name: "Claude (Anthropic)",
                apiUrl: "https://api.anthropic.com/v1",
                apiToken: "",
                modelName: "claude-3-haiku-20240307",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🧠"
            ),
            ConnectionProfile(
                name: "OpenRouter",
                apiUrl: "https://openrouter.ai/api/v1",
                apiToken: "",
                modelName: "meta-llama/llama-3.2-3b-instruct:free",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🚀"
            )
        ]
    }
    
    // MARK: - Private Methods
    
    private func updateActiveProfile(_ profile: ConnectionProfile) {
        if let index = connectionProfiles.firstIndex(where: { $0.id == profile.id }) {
            connectionProfiles[index] = profile
        }
    }
    
    private func migrateOldSettings() {
        let oldApiUrl = userDefaults.string(forKey: "apiUrl") ?? ""
        let oldApiToken = userDefaults.string(forKey: "apiToken") ?? ""
        let oldModelName = userDefaults.string(forKey: "modelName") ?? ""
        
        guard !oldApiUrl.isEmpty, !oldApiToken.isEmpty, !oldModelName.isEmpty, connectionProfiles.isEmpty else {
            return
        }
        
        let savedTemperature = userDefaults.double(forKey: "temperature")
        let temperature = savedTemperature == 0 ? 0.3 : savedTemperature
        
        let savedMaxTokens = userDefaults.integer(forKey: "maxTokens")
        let maxTokens = savedMaxTokens == 0 ? 1024 : savedMaxTokens
        
        let defaultProfile = ConnectionProfile(
            name: "Основной профиль",
            apiUrl: oldApiUrl,
            apiToken: oldApiToken,
            modelName: oldModelName,
            temperature: temperature,
            maxTokens: maxTokens,
            icon: "🌐"
        )
        
        connectionProfiles = [defaultProfile]
        activeProfileId = defaultProfile.id
        
        // Удаляем старые ключи
        userDefaults.removeObject(forKey: "apiUrl")
        userDefaults.removeObject(forKey: "apiToken")
        userDefaults.removeObject(forKey: "modelName")
        userDefaults.removeObject(forKey: "temperature")
        userDefaults.removeObject(forKey: "maxTokens")
        
        saveSettings()
    }
}
