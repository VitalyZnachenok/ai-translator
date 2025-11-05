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
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
