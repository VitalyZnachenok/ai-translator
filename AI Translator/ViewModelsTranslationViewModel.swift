//
//  TranslationViewModel.swift
//  AI Translator
//
//  Общий ViewModel для логики перевода
//

import SwiftUI
import AppKit
import Observation
import os

@Observable
@MainActor
final class TranslationViewModel {
    // MARK: - Published State
    
    var inputText = ""
    var outputText = ""
    var isTranslating = false
    var selectedSourceLanguage = "auto"
    var selectedTargetLanguage = "ru"
    var selectedPromptId = "default"
    var errorMessage = ""
    var showingError = false
    var copyFeedback = false
    
    // MARK: - Private Properties
    
    private let translationService = TranslationService()
    private var settingsManager: SettingsManager?
    private var keyEventMonitor: Any?
    private var notificationObserver: Any?
    private var copyFeedbackTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.vitaly.ai-translator", category: "TranslationViewModel")
    
    // MARK: - Computed Properties
    
    var isConfigured: Bool {
        settingsManager?.isConfigured ?? false
    }
    
    var canTranslate: Bool {
        !inputText.isEmpty && !isTranslating && isConfigured
    }
    
    var connectionProfiles: [ConnectionProfile] {
        settingsManager?.connectionProfiles ?? []
    }
    
    var activeProfileId: String {
        settingsManager?.activeProfileId ?? ""
    }
    
    var activeProfile: ConnectionProfile? {
        settingsManager?.activeProfile
    }
    
    var customPrompts: [TranslationPrompt] {
        settingsManager?.customPrompts ?? []
    }
    
    var currentPrompt: TranslationPrompt? {
        customPrompts.first { $0.id == selectedPromptId }
    }
    
    var formattedOutput: AttributedString {
        guard !outputText.isEmpty else {
            var placeholder = AttributedString("Результат перевода появится здесь...")
            placeholder.foregroundColor = .secondary
            return placeholder
        }
        if let md = try? AttributedString(
            markdown: outputText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return md
        }
        return AttributedString(outputText)
    }
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        cleanup()
    }
    
    // MARK: - Configuration
    
    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
        Task {
            await translationService.configure(with: settings)
        }
    }
    
    // MARK: - Profile Management
    
    func setActiveProfile(_ profileId: String) {
        settingsManager?.setActiveProfile(profileId)
    }
    
    // MARK: - Translation Actions
    
    func translate() {
        performTranslation(withExplanation: false)
    }
    
    func translateWithExplanation() {
        performTranslation(withExplanation: true)
    }
    
    private func performTranslation(withExplanation: Bool) {
        guard canTranslate, let settings = settingsManager else { return }
        
        isTranslating = true
        outputText = ""
        errorMessage = ""
        
        var customPrompt = settings.customPrompts.first { $0.id == selectedPromptId }
        
        // Если нужен перевод с пояснениями, модифицируем промпт
        if withExplanation {
            customPrompt = createExplanationPrompt(basePrompt: customPrompt)
        }
        
        Task {
            do {
                logger.debug("Starting translation (withExplanation: \(withExplanation))...")
                let result = try await translationService.translate(
                    text: inputText,
                    from: selectedSourceLanguage,
                    to: selectedTargetLanguage,
                    customPrompt: customPrompt
                )
                
                outputText = result
                isTranslating = false
                logger.debug("Translation completed successfully")
            } catch {
                logger.error("Translation failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showingError = true
                isTranslating = false
            }
        }
    }
    
    private func createExplanationPrompt(basePrompt: TranslationPrompt?) -> TranslationPrompt {
        let baseSystem = basePrompt?.systemPrompt ?? 
            "You are a professional translator and language teacher."
        
        return TranslationPrompt(
            name: "С пояснениями",
            description: "Перевод с комментариями и пояснениями",
            icon: "📝",
            systemPrompt: """
            \(baseSystem)
            
            Помимо перевода, ты также объясняешь свой выбор слов и конструкций. 
            Ты помогаешь пользователю лучше понять язык.
            """,
            userPromptAddition: """
            
            После перевода добавь раздел "📝 Пояснения:", где объясни:
            - Почему выбраны именно такие слова или фразы
            - Есть ли альтернативные варианты перевода и когда их лучше использовать
            - Особенности грамматики или идиом, если они есть
            - Нюансы стиля и тона (формальный/неформальный)
            
            Формат ответа:
            
            **Перевод:**
            [твой перевод]
            
            **📝 Пояснения:**
            [твои комментарии]
            """
        )
    }
    
    func swapLanguages() {
        guard selectedSourceLanguage != "auto" else { return }
        
        let tempLang = selectedSourceLanguage
        selectedSourceLanguage = selectedTargetLanguage
        selectedTargetLanguage = tempLang
        
        let tempText = inputText
        inputText = outputText
        outputText = tempText
    }
    
    func clearInput() {
        inputText = ""
    }
    
    func clearOutput() {
        outputText = ""
    }
    
    func clearAll() {
        inputText = ""
        outputText = ""
    }
    
    // MARK: - Clipboard Actions
    
    func copyToClipboard() {
        guard !outputText.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
        
        // Cancel previous feedback task if exists
        copyFeedbackTask?.cancel()
        
        copyFeedback = true
        
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copyFeedback = false
        }
    }
    
    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            inputText = string
        }
    }
    
    // MARK: - Input Validation
    
    func validateInputLength() {
        if inputText.count > 5000 {
            inputText = String(inputText.prefix(5000))
        }
    }
    
    // MARK: - Event Monitoring
    
    func setupKeyboardShortcuts() {
        // Удаляем предыдущий монитор если есть
        removeKeyboardShortcuts()
        
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            
            // Cmd+Enter для перевода
            if event.modifierFlags.contains(.command) && event.keyCode == 36 && self.canTranslate {
                Task { @MainActor in
                    self.translate()
                }
                return nil
            }
            return event
        }
    }
    
    func removeKeyboardShortcuts() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    func setupQuickTranslateListener() {
        // Удаляем предыдущий observer если есть
        removeQuickTranslateListener()
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("QuickTranslateText"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleQuickTranslateNotification(notification)
            }
        }
    }
    
    func removeQuickTranslateListener() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func handleQuickTranslateNotification(_ notification: Notification) {
        var text: String?
        
        if let userInfoText = notification.userInfo?["text"] as? String {
            text = userInfoText
        } else if let defaultsText = UserDefaults.standard.string(forKey: "pendingTranslationText") {
            text = defaultsText
            UserDefaults.standard.removeObject(forKey: "pendingTranslationText")
        }
        
        guard let finalText = text, !finalText.isEmpty else { return }
        
        logger.debug("Quick translate text received: \(finalText.prefix(50))...")
        inputText = finalText
        
        if isConfigured {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                translate()
            }
        }
    }
    
    private nonisolated func cleanup() {
        // Выполняем cleanup на main actor
        Task { @MainActor [weak self] in
            self?.removeKeyboardShortcuts()
            self?.removeQuickTranslateListener()
            self?.copyFeedbackTask?.cancel()
        }
    }
}
