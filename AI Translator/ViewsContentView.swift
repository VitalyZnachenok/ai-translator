//
//  ContentView.swift
//  AI Translator
//
//  Главное окно переводчика
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var showingSettings = false
    @State private var selectedSourceLanguage = "auto"
    @State private var selectedTargetLanguage = "ru"
    @State private var selectedPromptId = "default"
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var copyFeedback = false
    @State private var keyEventMonitor: Any?
    @State private var notificationObserver: Any?
    
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Заголовок
            HStack {
                Image(systemName: "globe")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("AI Переводчик")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Селектор профилей
                    if !settingsManager.connectionProfiles.isEmpty {
                        Menu {
                            ForEach(settingsManager.connectionProfiles) { profile in
                                Button(action: {
                                    settingsManager.setActiveProfile(profile.id)
                                }) {
                                    HStack {
                                        Text(profile.displayName)
                                        if settingsManager.activeProfileId == profile.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let activeProfile = settingsManager.activeProfile {
                                    Text(activeProfile.icon)
                                        .font(.caption)
                                    Text(activeProfile.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .help("Переключить профиль подключения")
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settingsManager.isConfigured ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(settingsManager.isConfigured ? "Подключено" : "Не настроено")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Настройки (⌘,)")
            }
            .padding(.horizontal)
            
            // Выбор языков
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("С какого языка:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Исходный язык", selection: $selectedSourceLanguage) {
                        ForEach(LanguageData.fullLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 200)
                }
                
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedSourceLanguage == "auto")
                .help("Поменять языки местами")
                
                VStack(alignment: .leading) {
                    Text("На какой язык:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Целевой язык", selection: $selectedTargetLanguage) {
                        ForEach(LanguageData.fullLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 200)
                }
            }
            .padding(.horizontal)
            
            // Выбор стиля перевода
            HStack {
                VStack(alignment: .leading) {
                    Text("Стиль перевода:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Стиль", selection: $selectedPromptId) {
                        Text("🎯 Стандартный").tag("default")
                        ForEach(settingsManager.customPrompts) { prompt in
                            Text(prompt.icon + " " + prompt.name).tag(prompt.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(minWidth: 200)
                }
                
                Spacer()
                
                if let currentPrompt = settingsManager.customPrompts.first(where: { $0.id == selectedPromptId }) {
                    Text(currentPrompt.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 300)
                }
            }
            .padding(.horizontal)
            
            // Поле ввода
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Текст для перевода:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !inputText.isEmpty {
                        Button(action: { inputText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Очистить текст")
                    }
                    
                    Text("\(inputText.count)/5000")
                        .font(.caption)
                        .foregroundColor(inputText.count > 4500 ? .red : .secondary)
                }
                
                TextEditor(text: $inputText)
                    .font(.body)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(minHeight: 120, maxHeight: 200)
                    .onChange(of: inputText) { _, newValue in
                        if newValue.count > 5000 {
                            inputText = String(newValue.prefix(5000))
                        }
                    }
            }
            .padding(.horizontal)
            
            // Кнопка перевода
            HStack(spacing: 12) {
                Button(action: translateText) {
                    HStack {
                        if isTranslating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        Text(isTranslating ? "Переводим..." : "Перевести")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(radius: 2)
                }
                .disabled(inputText.isEmpty || isTranslating || !settingsManager.isConfigured)
                .buttonStyle(PlainButtonStyle())
                .help("Перевести текст (⌘↩)")
                
                Text("⌘↩")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Нажмите Cmd+Enter для быстрого перевода")
                
                Button(action: pasteFromClipboard) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Вставить")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Вставить текст из буфера обмена")
            }
            
            // Результат перевода
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Результат перевода:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !outputText.isEmpty {
                        HStack(spacing: 8) {
                            Button(action: copyToClipboard) {
                                HStack(spacing: 4) {
                                    Image(systemName: copyFeedback ? "checkmark" : "doc.on.clipboard")
                                        .foregroundColor(copyFeedback ? .green : .blue)
                                    Text(copyFeedback ? "Скопировано!" : "Копировать")
                                        .foregroundColor(copyFeedback ? .green : .blue)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Копировать перевод в буфер обмена")
                            
                            Button(action: { outputText = "" }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Очистить результат")
                        }
                    }
                }
                
                ScrollView {
                    Text(outputText.isEmpty ? "Результат перевода появится здесь..." : outputText)
                        .font(.body)
                        .foregroundColor(outputText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: 250)
            }
            .padding(.horizontal)
            
            if !settingsManager.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Настройте подключение к OpenWebUI в настройках")
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Открыть настройки") {
                        showingSettings = true
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settingsManager: settingsManager)
        }
        .alert("Ошибка", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            translationService.configure(with: settingsManager)
            setupKeyboardShortcuts()
            setupQuickTranslateListener()
        }
        .onDisappear {
            removeKeyboardShortcuts()
            removeQuickTranslateListener()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) &&
               event.keyCode == 36 &&
               !self.inputText.isEmpty &&
               !self.isTranslating &&
               self.settingsManager.isConfigured {
                self.translateText()
                return nil
            }
            return event
        }
    }
    
    private func removeKeyboardShortcuts() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    private func setupQuickTranslateListener() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("QuickTranslateText"),
            object: nil,
            queue: .main
        ) { notification in
            print("📥 QuickTranslateText notification received in ContentView")
            
            var text: String?
            
            if let userInfoText = notification.userInfo?["text"] as? String {
                text = userInfoText
                print("✅ Text from userInfo: \(userInfoText.prefix(50))")
            } else if let defaultsText = UserDefaults.standard.string(forKey: "pendingTranslationText") {
                text = defaultsText
                print("✅ Text from UserDefaults: \(defaultsText.prefix(50))")
                UserDefaults.standard.removeObject(forKey: "pendingTranslationText")
            }
            
            guard let finalText = text, !finalText.isEmpty else {
                print("❌ No text found in notification")
                return
            }
            
            self.inputText = finalText
            print("✅ Input text set: \(finalText.prefix(50))")
            
            if self.settingsManager.isConfigured {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("🚀 Starting translation...")
                    self.translateText()
                }
            } else {
                print("⚠️ Settings not configured")
            }
        }
    }
    
    private func removeQuickTranslateListener() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }
    
    private func swapLanguages() {
        guard selectedSourceLanguage != "auto" else { return }
        let temp = selectedSourceLanguage
        selectedSourceLanguage = selectedTargetLanguage
        selectedTargetLanguage = temp
        
        let tempText = inputText
        inputText = outputText
        outputText = tempText
    }
    
    private func translateText() {
        guard !inputText.isEmpty, settingsManager.isConfigured else { return }
        
        isTranslating = true
        outputText = ""
        errorMessage = ""
        
        let customPrompt = settingsManager.customPrompts.first(where: { $0.id == selectedPromptId })
        
        Task {
            do {
                let result = try await translationService.translate(
                    text: inputText,
                    from: selectedSourceLanguage,
                    to: selectedTargetLanguage,
                    customPrompt: customPrompt
                )
                
                await MainActor.run {
                    outputText = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isTranslating = false
                }
            }
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copyFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copyFeedback = false
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            inputText = string
        }
    }
}
