//
//  ModelService.swift
//  AI Translator
//
//  Сервис для загрузки списка доступных моделей из OpenWebUI
//

import Foundation

class ModelService: ObservableObject {
    private var session: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }
    
    func fetchAvailableModels(apiUrl: String, apiToken: String) async throws -> [OpenWebUIModel] {
        var urlString = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Убираем завершающий слеш если есть
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        
        // Формируем правильный URL для моделей
        urlString = buildModelsURL(from: urlString)
        
        print("Запрос моделей по URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AI-Translator/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("Error response: \(responseString)")
            
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = errorData["detail"] as? String {
                    throw TranslationError.apiError(detail)
                } else if let error = errorData["error"] as? [String: Any],
                          let message = error["message"] as? String {
                    throw TranslationError.apiError(message)
                }
            }
            throw TranslationError.httpError(httpResponse.statusCode)
        }
        
        return try parseModelsResponse(data: data)
    }
    
    // MARK: - Private Methods
    
    private func buildModelsURL(from urlString: String) -> String {
        var result = urlString
        
        if result.hasSuffix("/api") {
            result += "/v1/models"
        } else if result.hasSuffix("/api/v1") {
            result += "/models"
        } else if result.contains("/api/v1/chat/completions") {
            result = result.replacingOccurrences(of: "/chat/completions", with: "/models")
        } else if !result.contains("/models") {
            if result.contains("/api") && !result.contains("/v1") {
                result += "/v1/models"
            } else if result.contains("/v1") {
                result += "/models"
            } else {
                result += "/api/v1/models"
            }
        }
        
        return result
    }
    
    private func parseModelsResponse(data: Data) throws -> [OpenWebUIModel] {
        // Пробуем стандартный формат OpenAI API
        do {
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            print("✅ Successfully parsed \(modelsResponse.data.count) models using standard format")
            return sortModels(modelsResponse.data)
        } catch {
            print("❌ Standard format failed: \(error)")
        }
        
        // Пробуем формат с полем "models"
        do {
            let directResponse = try JSONDecoder().decode(DirectModelsResponse.self, from: data)
            print("✅ Successfully parsed \(directResponse.models.count) models using direct format")
            return sortModels(directResponse.models)
        } catch {
            print("❌ Direct format failed: \(error)")
        }
        
        // Пробуем простой массив моделей
        do {
            let arrayResponse = try JSONDecoder().decode(ModelsArrayResponse.self, from: data)
            print("✅ Successfully parsed \(arrayResponse.count) models using array format")
            return sortModels(arrayResponse)
        } catch {
            print("❌ All JSON decode attempts failed")
            print("Final decode error: \(error)")
            throw TranslationError.invalidResponse
        }
    }
    
    private func sortModels(_ models: [OpenWebUIModel]) -> [OpenWebUIModel] {
        return models.sorted { 
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending 
        }
    }
}
