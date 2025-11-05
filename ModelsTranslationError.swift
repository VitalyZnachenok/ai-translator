//
//  TranslationError.swift
//  AI Translator
//
//  Типы ошибок для перевода
//

import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidRequest
    case networkError
    case networkTimeout
    case noInternetConnection
    case httpError(Int)
    case apiError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Настройки не сконфигурированы. Проверьте URL API, токен и модель."
        case .invalidURL:
            return "Неверный URL API. Проверьте настройки."
        case .invalidRequest:
            return "Ошибка формирования запроса."
        case .networkError:
            return "Ошибка сети. Проверьте интернет соединение и попробуйте снова."
        case .networkTimeout:
            return "Превышено время ожидания ответа. Проверьте соединение и попробуйте снова."
        case .noInternetConnection:
            return "Нет подключения к интернету. Проверьте сетевые настройки."
        case .httpError(let code):
            return "HTTP ошибка: \(code). \(httpErrorDescription(code))"
        case .apiError(let message):
            return "Ошибка API: \(message)"
        case .invalidResponse:
            return "Неверный формат ответа от сервера."
        }
    }
    
    private func httpErrorDescription(_ code: Int) -> String {
        switch code {
        case 401:
            return "Неверный API токен."
        case 403:
            return "Доступ запрещен. Проверьте права доступа."
        case 404:
            return "API endpoint не найден. Проверьте URL."
        case 429:
            return "Слишком много запросов. Попробуйте позже."
        case 500...599:
            return "Ошибка сервера. Попробуйте позже."
        default:
            return "Проверьте настройки API."
        }
    }
}
