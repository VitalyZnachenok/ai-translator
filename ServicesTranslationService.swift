//
//  TranslationService.swift
//  AI Translator
//
//  Сервис для выполнения переводов через OpenAI-совместимый chat/completions API.
//

import Foundation
import os

/// Результат перевода вместе с фактически использованным направлением.
struct TranslationResult {
    let text: String
    let direction: ResolvedDirection
    /// Понадобился ли повторный запрос, потому что модель ответила на исходном языке.
    let retriedForLanguage: Bool

    var sourceLanguage: String { direction.source }
    var targetLanguage: String { direction.target }
}

/// События потокового перевода.
enum TranslationStreamEvent {
    /// Направление определено (до первого запроса к модели).
    case direction(ResolvedDirection)
    /// Накопленный видимый текст (блоки рассуждений уже вырезаны).
    case text(String)
    /// Перевод завершён; `text` здесь окончательный (мог быть заменён после проверки языка).
    case completed(TranslationResult)
}

actor TranslationService {
    // MARK: - Properties

    private let session: URLSession
    private var settingsManager: SettingsManager?
    private let logger = Logger(subsystem: "com.vitaly.ai-translator", category: "TranslationService")

    /// HTTP-статусы, при которых запрос имеет смысл повторить.
    private static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    // MARK: - Initialization

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Configuration

    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
    }

    // MARK: - Translation

    /// Переводит текст одним запросом (без стриминга).
    ///
    /// - Parameter verifyOutputLanguage: после ответа проверить локальным детектором,
    ///   что результат действительно на целевом языке, и при необходимости повторить
    ///   запрос с усиленной инструкцией. Отключается для режимов, где ответ по замыслу
    ///   смешанный (например, перевод с пояснениями).
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        customPrompt: TranslationPrompt? = nil,
        verifyOutputLanguage: Bool = true
    ) async throws -> TranslationResult {
        guard let settings = settingsManager, settings.isConfigured else {
            throw TranslationError.notConfigured
        }

        let direction = resolveDirection(text: text, from: sourceLanguage, to: targetLanguage, settings: settings)
        logDirection(direction, requestedTarget: targetLanguage)

        let request = try buildRequest(
            text: text, direction: direction, customPrompt: customPrompt,
            settings: settings, stream: false, insist: false
        )
        var result = try await performRequestWithRetry(request: request)
        var finalDirection = direction
        var retried = false

        if verifyOutputLanguage, let corrected = Self.retryDirection(for: result, direction: direction, settings: settings) {
            logger.warning("Answer is not in \(direction.target) (\(direction.label)); retrying as \(corrected.label) with a stricter prompt")
            let strictRequest = try buildRequest(
                text: text, direction: corrected, customPrompt: customPrompt,
                settings: settings, stream: false, insist: true
            )
            result = try await performRequestWithRetry(request: strictRequest)
            finalDirection = corrected
            retried = true
        }

        return TranslationResult(text: result, direction: finalDirection, retriedForLanguage: retried)
    }

    /// Потоковый перевод для окна: текст появляется по мере генерации.
    ///
    /// Если сервер не поддерживает стриминг или соединение оборвалось до первого
    /// токена, выполняется обычный запрос через `translate`.
    func translateStream(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        customPrompt: TranslationPrompt? = nil,
        verifyOutputLanguage: Bool = true
    ) -> AsyncThrowingStream<TranslationStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let settings = self.settingsManager, settings.isConfigured else {
                        throw TranslationError.notConfigured
                    }
                    let direction = self.resolveDirection(text: text, from: sourceLanguage, to: targetLanguage, settings: settings)
                    self.logDirection(direction, requestedTarget: targetLanguage)
                    continuation.yield(.direction(direction))

                    let request = try self.buildRequest(
                        text: text, direction: direction, customPrompt: customPrompt,
                        settings: settings, stream: true, insist: false
                    )

                    var raw = ""
                    do {
                        raw = try await self.streamCompletion(request: request) { accumulated in
                            continuation.yield(.text(Self.visibleText(accumulated)))
                        }
                    } catch let error as URLError where raw.isEmpty && error.code != .cancelled {
                        // Ничего не успели получить — повторяем обычным запросом с ретраями.
                        self.logger.warning("Streaming failed before first token (\(error.localizedDescription)); falling back to a plain request")
                        let fallback = try await self.translate(
                            text: text, from: sourceLanguage, to: targetLanguage,
                            customPrompt: customPrompt, verifyOutputLanguage: verifyOutputLanguage
                        )
                        continuation.yield(.text(fallback.text))
                        continuation.yield(.completed(fallback))
                        continuation.finish()
                        return
                    }

                    var final = Self.visibleText(raw)
                    var finalDirection = direction
                    var retried = false
                    if verifyOutputLanguage,
                       let corrected = Self.retryDirection(for: final, direction: direction, settings: settings) {
                        self.logger.warning("Streamed answer is not in \(direction.target) (\(direction.label)); retrying as \(corrected.label) with a stricter prompt")
                        let strictRequest = try self.buildRequest(
                            text: text, direction: corrected, customPrompt: customPrompt,
                            settings: settings, stream: false, insist: true
                        )
                        final = try await self.performRequestWithRetry(request: strictRequest)
                        finalDirection = corrected
                        retried = true
                        continuation.yield(.direction(finalDirection))
                        continuation.yield(.text(final))
                    }

                    continuation.yield(.completed(TranslationResult(text: final, direction: finalDirection, retriedForLanguage: retried)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Direction

    private func resolveDirection(text: String, from source: String, to target: String,
                                  settings: SettingsManager) -> ResolvedDirection {
        TranslationDirectionResolver.resolve(
            text: text,
            requestedSource: source,
            requestedTarget: target,
            pairs: settings.inPlaceLanguagePairs,
            fallbackSource: settings.lastSourceLanguage
        )
    }

    private func logDirection(_ direction: ResolvedDirection, requestedTarget: String) {
        if direction.targetChanged {
            logger.info("Direction: \(direction.label) (target \(requestedTarget) matched the detected source, switched)")
        } else {
            logger.debug("Direction: \(direction.label) (detected: \(direction.detected ?? "-"))")
        }
    }

    /// Проверяет язык ответа локальным детектором. Возвращает направление для
    /// повторного запроса, если ответ не на целевом языке, иначе `nil`.
    ///
    /// * Источник известен: ответ сравнивается только между исходным и целевым
    ///   языком; уверенное совпадение с исходным — повтор того же направления.
    /// * Источник «auto» (детектор не справился с входом): язык ответа ищется
    ///   среди всех поддерживаемых. Локальные модели игнорируют правило «если
    ///   текст уже на целевом языке, переведи на другой» и возвращают исходник,
    ///   поэтому повтор идёт с явным направлением: найденный язык → цель (или
    ///   другой язык пары, если найденный и есть цель).
    static func retryDirection(for answer: String, direction: ResolvedDirection,
                               settings: SettingsManager) -> ResolvedDirection? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if direction.source != "auto" {
            guard direction.source != direction.target else { return nil }
            let detected = LanguageDetector.detect(
                trimmed,
                among: [direction.source, direction.target],
                minimumConfidence: 0.85
            )
            return detected == direction.source ? direction : nil
        }

        guard let detected = LanguageDetector.detect(trimmed, minimumConfidence: 0.85),
              detected != direction.target else { return nil }
        let target = TranslationDirectionResolver.alternativeTarget(
            for: detected, pairs: settings.inPlaceLanguagePairs, fallbackSource: settings.lastSourceLanguage
        )
        return ResolvedDirection(
            source: detected,
            target: detected == direction.target ? target : direction.target,
            detected: detected,
            targetChanged: detected == direction.target
        )
    }

    // MARK: - Request building

    private func buildRequest(
        text: String,
        direction: ResolvedDirection,
        customPrompt: TranslationPrompt?,
        settings: SettingsManager,
        stream: Bool,
        insist: Bool
    ) throws -> URLRequest {
        let url = try buildURL(from: settings.apiUrl)

        let systemMessage = customPrompt?.systemPrompt ??
            "You are a professional translator. Translate accurately while preserving the tone and style of the original text."
        let userMessage = Self.makeUserPrompt(
            text: text,
            direction: direction,
            additionalInstructions: customPrompt?.userPromptAddition ?? "",
            pairs: settings.inPlaceLanguagePairs,
            fallbackSource: settings.lastSourceLanguage,
            insist: insist
        )

        var body: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessage]
            ],
            "temperature": insist ? min(settings.temperature, 0.1) : settings.temperature,
            // Лимит в профиле — нижняя граница: длинный текст (особенно CJK или с
            // пояснениями) не должен обрезаться молча. Верхняя граница — 8192.
            "max_tokens": max(settings.maxTokens, min(text.count * 2 + 256, 8192)),
            "stream": stream
        ]

        // Управление мышлением думающих моделей (Ollama OpenAI-совместимый API:
        // "none" — выключить, "low"/"medium"/"high" — уровень). Если выбран
        // вариант "по умолчанию" — параметр не отправляем, чтобы не сломать
        // серверы, которые его не поддерживают.
        if let effort = settings.reasoningEffort.apiValue {
            body["reasoning_effort"] = effort
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AI-Translator/1.0", forHTTPHeaderField: "User-Agent")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw TranslationError.invalidRequest
        }
        return request
    }

    private func buildURL(from apiUrl: String) throws -> URL {
        var urlString = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        if !urlString.hasSuffix("/") {
            urlString += "/"
        }

        if !urlString.hasSuffix("chat/completions/") {
            urlString += "chat/completions"
        } else {
            urlString.removeLast()
        }

        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        return url
    }

    // MARK: - Prompt

    /// Названия языков для промпта. Инструкции на английском: их модели выполняют
    /// надёжнее всего, а язык инструкции не подталкивает модель отвечать на нём.
    private static let languageNames: [String: String] = [
        "en": "English", "ru": "Russian", "zh": "Chinese (Simplified)",
        "es": "Spanish", "fr": "French", "de": "German",
        "ja": "Japanese", "ko": "Korean", "it": "Italian",
        "pt": "Portuguese", "ar": "Arabic", "hi": "Hindi",
        "tr": "Turkish", "uk": "Ukrainian", "pl": "Polish"
    ]

    static func languageName(_ code: String) -> String {
        languageNames[code] ?? code
    }

    static func makeUserPrompt(
        text: String,
        direction: ResolvedDirection,
        additionalInstructions: String,
        pairs: [LanguagePair],
        fallbackSource: String?,
        insist: Bool
    ) -> String {
        let target = languageName(direction.target)
        var lines: [String] = []

        if direction.source == "auto" {
            // Детектор не справился — пусть язык определит модель, но с явным
            // правилом на случай, если текст уже на целевом языке.
            let alternative = languageName(
                TranslationDirectionResolver.alternativeTarget(
                    for: direction.target, pairs: pairs, fallbackSource: fallbackSource
                )
            )
            lines.append("Translate the text between the <text> tags into \(target). Detect the source language yourself.")
            lines.append("If the text is already in \(target), translate it into \(alternative) instead.")
        } else {
            let source = languageName(direction.source)
            lines.append("Translate the text between the <text> tags from \(source) into \(target).")
        }

        lines.append("Preserve the meaning, tone and register. Keep the original formatting: line breaks, lists, Markdown, URLs, code, numbers and placeholders.")
        lines.append("Reply with the \(target) translation only: no explanations, no notes, no quotation marks, no preamble.")
        if direction.source != "auto" {
            lines.append("The entire reply must be in \(target). Never return or paraphrase the text in \(languageName(direction.source)).")
        } else {
            lines.append("The entire reply must be in the target language.")
        }

        if insist, direction.source != "auto" {
            lines.append("IMPORTANT: your previous reply was still in \(languageName(direction.source)). This time produce the \(target) translation.")
        }

        let extra = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            lines.append("")
            lines.append("Additional style instructions:")
            lines.append(extra)
        }

        lines.append("")
        lines.append("<text>")
        lines.append(text)
        lines.append("</text>")

        return lines.joined(separator: "\n")
    }

    // MARK: - Networking

    private func performRequestWithRetry(request: URLRequest, maxRetries: Int = 3) async throws -> String {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TranslationError.networkError
                }

                if httpResponse.statusCode != 200 {
                    if Self.retryableStatuses.contains(httpResponse.statusCode), attempt < maxRetries {
                        let delay = Self.retryDelay(for: httpResponse, attempt: attempt)
                        logger.warning("HTTP \(httpResponse.statusCode) on attempt \(attempt); retrying in \(delay, format: .fixed(precision: 1)) s")
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
                }

                return try parseTranslationResponse(data: data)

            } catch {
                if error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                    || Task.isCancelled {
                    throw error
                }

                lastError = error
                logger.warning("Translation attempt \(attempt) failed: \(error.localizedDescription)")

                if !(error is URLError) || attempt == maxRetries {
                    throw convertError(error)
                }

                try await Task.sleep(for: .seconds(attempt))
            }
        }

        throw lastError ?? TranslationError.networkError
    }

    /// Пауза перед повтором: `Retry-After` сервера (не больше 10 с) или линейный backoff.
    private static func retryDelay(for response: HTTPURLResponse, attempt: Int) -> Double {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
            return min(max(seconds, 0.5), 10)
        }
        return Double(attempt) * 1.5
    }

    /// Читает SSE-поток chat/completions. Вызывает `onUpdate` с накопленным сырым
    /// текстом после каждого фрагмента и возвращает полный сырой текст.
    private func streamCompletion(request: URLRequest, onUpdate: (String) -> Void) async throws -> String {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError
        }
        if httpResponse.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        var accumulated = ""
        var sawDelta = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                throw TranslationError.apiError(message)
            }
            guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else { continue }

            var chunk: String?
            if let delta = first["delta"] as? [String: Any] {
                chunk = delta["content"] as? String
            } else if let message = first["message"] as? [String: Any] {
                // Сервер проигнорировал stream=true и прислал обычный ответ в одной строке.
                chunk = message["content"] as? String
            }
            if let chunk, !chunk.isEmpty {
                accumulated += chunk
                sawDelta = true
                onUpdate(accumulated)
            }
        }

        if !sawDelta && accumulated.isEmpty {
            throw TranslationError.invalidResponse
        }
        return accumulated
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }

        return Self.visibleText(content)
    }

    /// Текст без блоков рассуждений `<think>…</think>` (и аналогов), включая
    /// незакрытый блок в конце — для потокового режима, пока модель ещё «думает».
    static func visibleText(_ text: String) -> String {
        let patterns = [
            "(?is)<think>.*?</think>",
            "(?is)<thinking>.*?</thinking>",
            "(?is)<think>.*$",
            "(?is)<thinking>.*$"
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertError(_ error: Error) -> Error {
        if error is TranslationError {
            return error
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return TranslationError.networkTimeout
            case .notConnectedToInternet:
                return TranslationError.noInternetConnection
            default:
                return TranslationError.networkError
            }
        }

        return TranslationError.networkError
    }
}
