//
//  OpenWebUIModel.swift
//  AI Translator
//
//  Модели для работы с OpenWebUI API
//

import Foundation

struct OpenWebUIModel: Codable, Identifiable {
    let id: String
    let name: String?
    let object: String?
    let owned_by: String?
    let created: Int?
    
    // Дополнительные поля для Ollama
    let ollama: OllamaInfo?
    let connection_type: String?
    let tags: [String]?
    let actions: [String]?
    let filters: [String]?
    let arena: Bool?
    let info: ModelInfo?
    
    // Альтернативные поля
    let model: String?
    
    var displayName: String {
        let modelName = name ?? model ?? id
        let cleanName = modelName
            .replacingOccurrences(of: "ollama:", with: "")
            .replacingOccurrences(of: "openai:", with: "")
            .replacingOccurrences(of: "anthropic:", with: "")
            .replacingOccurrences(of: "google:", with: "")
        return cleanName.isEmpty ? id : cleanName
    }
    
    var providerIcon: String {
        let modelName = name ?? model ?? id
        
        if modelName.contains("gpt") || modelName.contains("openai") {
            return "🤖"
        } else if modelName.contains("claude") || modelName.contains("anthropic") {
            return "🧠"
        } else if modelName.contains("gemini") || modelName.contains("google") || modelName.contains("gemma") {
            return "💎"
        } else if modelName.contains("llama") {
            return "🦙"
        } else if modelName.contains("mistral") {
            return "🌪️"
        } else if modelName.contains("phi") {
            return "🔬"
        } else if modelName.contains("qwen") {
            return "🐧"
        } else if modelName.contains("arena") {
            return "🏟️"
        } else if owned_by == "ollama" || connection_type == "local" {
            return "🦙"
        } else {
            return "⚡"
        }
    }
}

// MARK: - Supporting Structures

struct OllamaInfo: Codable {
    let name: String?
    let model: String?
    let modified_at: String?
    let size: Int?
    let digest: String?
    let details: ModelDetails?
    let connection_type: String?
    let urls: [Int]?
    let expires_at: Int?
}

struct ModelDetails: Codable {
    let parent_model: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

struct ModelInfo: Codable {
    let meta: ModelMeta?
}

struct ModelMeta: Codable {
    let profile_image_url: String?
    let description: String?
    let model_ids: [String]?
}

// MARK: - API Response Formats

struct ModelsResponse: Codable {
    let data: [OpenWebUIModel]
    let object: String?
}

struct DirectModelsResponse: Codable {
    let models: [OpenWebUIModel]
}

typealias ModelsArrayResponse = [OpenWebUIModel]
