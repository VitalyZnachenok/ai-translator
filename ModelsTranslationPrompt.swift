//
//  TranslationPrompt.swift
//  AI Translator
//
//  Модель кастомного промпта для стилей перевода
//

import Foundation

struct TranslationPrompt: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var icon: String
    var systemPrompt: String
    var userPromptAddition: String
}
