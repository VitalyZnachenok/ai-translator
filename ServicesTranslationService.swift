//
//  TranslationService.swift
//  AI Translator
//
//  Сервис для выполнения переводов через OpenWebUI API
//

import Foundation

class TranslationService: ObservableObject {
    private var settingsManager: SettingsManager?
    private var session: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }
    
    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
    }
    
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        customPrompt: TranslationPrompt? = nil
    ) async throws -> String {
        guard let settings = settingsManager, settings.isConfigured else {
            throw TranslationError.notConfigured
        }
        
        let prompt = createTranslationPrompt(
            text: text,
            from: sourceLanguage,
            to: targetLanguage,
            customPrompt: customPrompt
        )
        
        let url = try buildURL(from: settings.apiUrl)
        let requestBody = buildRequestBody(
            prompt: prompt,
            settings: settings,
            customPrompt: customPrompt
        )
        
        let request = try buildRequest(url: url, body: requestBody, token: settings.apiToken)
        
        return try await performRequestWithRetry(request: request)
    }
    
    // MARK: - Private Methods
    
    private func buildURL(from apiUrl: String) throws -> URL {
        var urlString = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        
        if !urlString.hasSuffix("chat/completions") && !urlString.hasSuffix("v1/") {
            urlString += "chat/completions"
        } else if urlString.hasSuffix("v1/") {
            urlString += "chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }
        
        return url
    }
    
    private func buildRequestBody(
        prompt: String,
        settings: SettingsManager,
        customPrompt: TranslationPrompt?
    ) -> [String: Any] {
        let systemMessage = customPrompt?.systemPrompt ?? 
            "You are a professional translator. Translate accurately while preserving the tone and style of the original text."
        
        return [
            "model": settings.modelName,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": prompt]
            ],
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens,
            "stream": false
        ]
    }
    
    private func buildRequest(url: URL, body: [String: Any], token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AI-Translator/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw TranslationError.invalidRequest
        }
        
        return request
    }
    
    private func performRequestWithRetry(request: URLRequest) async throws -> String {
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TranslationError.networkError
                }
                
                if httpResponse.statusCode != 200 {
                    try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
                }
                
                return try parseTranslationResponse(data: data)
                
            } catch {
                lastError = error
                
                if !(error is URLError) || attempt == 3 {
                    throw convertError(error)
                }
                
                try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
            }
        }
        
        throw lastError ?? TranslationError.networkError
    }
    
    private func handleHTTPError(statusCode: Int, data: Data) throws {
        if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = errorData["detail"] as? String {
                throw TranslationError.apiError(detail)
            } else if let error = errorData["error"] as? [String: Any],
                      let message = error["message"] as? String {
                throw TranslationError.apiError(message)
            }
        }
        throw TranslationError.httpError(statusCode)
    }
    
    private func parseTranslationResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func convertError(_ error: Error) -> Error {
        if error is TranslationError {
            return error
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return TranslationError.networkTimeout
            case .notConnectedToInternet:
                return TranslationError.noInternetConnection
            default:
                return TranslationError.networkError
            }
        } else {
            return TranslationError.networkError
        }
    }
    
    private func createTranslationPrompt(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        customPrompt: TranslationPrompt?
    ) -> String {
        let languageNames: [String: String] = [
            "auto": "автоматически определить язык",
            "en": "английский", "ru": "русский", "zh": "китайский",
            "es": "испанский", "fr": "французский", "de": "немецкий",
            "ja": "японский", "ko": "корейский", "it": "итальянский",
            "pt": "португальский", "ar": "арабский", "hi": "хинди",
            "tr": "турецкий", "uk": "украинский", "pl": "польский"
        ]
        
        let sourceName = languageNames[sourceLanguage] ?? sourceLanguage
        let targetName = languageNames[targetLanguage] ?? targetLanguage
        
        let sourceInstruction = sourceLanguage == "auto"
            ? "Автоматически определи исходный язык текста и"
            : "Переведи с языка \(sourceName)"
        
        let additionalInstructions = customPrompt?.userPromptAddition ?? ""
        
        return """
        \(sourceInstruction) на \(targetName) следующий текст. 
        Сохрани стиль, тон и форматирование оригинала. 
        \(additionalInstructions)
        Верни только переведённый текст без дополнительных пояснений или комментариев.
        
        Текст для перевода:
        \(text)
        """
    }
}
