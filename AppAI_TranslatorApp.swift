//
//  AI_TranslatorApp.swift
//  AI Translator
//
//  Главный файл приложения
//

import SwiftUI

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Применяем выбранный язык интерфейса до построения UI.
        LocalizationManager.applyStartupLanguage()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
