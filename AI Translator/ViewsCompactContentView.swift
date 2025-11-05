//
//  CompactContentView.swift
//  AI Translator
//
//  Компактный вид для popover в menu bar
//

import SwiftUI
import AppKit

struct CompactContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
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
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                Text("AI Переводчик")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
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
                        if let activeProfile = settingsManager.activeProfile {
                            Text(activeProfile.icon)
                                .font(.caption2)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .help("Переключить профиль")
                }
                
                Circle()
                    .fill(settingsManager.isConfigured ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                
                Button(action: {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showMainWindow()
                    }
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Открыть полную версию (⌘O)")
            }
            .padding(.horizontal)
            
            HStack(spacing: 8) {
                Picker("От", selection: $selectedSourceLanguage) {
                    ForEach(LanguageData.compactLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
                
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedSourceLanguage == "auto")
                
                Picker("В", selection: $selectedTargetLanguage) {
                    ForEach(LanguageData.compactLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
                
                Spacer()
                
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Вставить из буфера")
            }
            .padding(.horizontal)
            
            if !settingsManager.customPrompts.isEmpty {
                HStack {
                    Picker("Стиль", selection: $selectedPromptId) {
                        Text("🎯").tag("default")
                        ForEach(settingsManager.customPrompts) { prompt in
                            Text(prompt.icon).tag(prompt.id)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Текст:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !inputText.isEmpty {
                        Button(action: { inputText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Text("\(inputText.count)/5000")
                        .font(.caption2)
                        .foregroundColor(inputText.count > 4500 ? .red : .secondary)
                }
                
                TextEditor(text: $inputText)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .frame(minHeight: 80, maxHeight: 120)
                    .onChange(of: inputText) { _, newValue in
                        if newValue.count > 5000 {
                            inputText = String(newValue.prefix(5000))
                        }
                    }
            }
            .padding(.horizontal)
            
            Button(action: translateText) {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(isTranslating ? "Переводим..." : "Перевести")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
            }
            .disabled(inputText.isEmpty || isTranslating || !settingsManager.isConfigured)
            .buttonStyle(PlainButtonStyle())
            .help("Перевести текст (⌘↩)")
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Результат:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !outputText.isEmpty {
                        Button(action: copyToClipboard) {
                            Image(systemName: copyFeedback ? "checkmark" : "doc.on.clipboard")
                                .font(.caption)
                                .foregroundColor(copyFeedback ? .green : .blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Копировать")
                    }
                }
                
                ScrollView {
                    Text(outputText.isEmpty ? "Результат появится здесь..." : outputText)
                        .font(.system(size: 12))
                        .foregroundColor(outputText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 80, maxHeight: 150)
            }
            .padding(.horizontal)
            
            if !settingsManager.isConfigured {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("Настройте подключение")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Настройки") {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.showSettings()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(LinkButtonStyle())
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            translationService.configure(with: settingsManager)
            setupKeyboardShortcuts()
            setupQuickTranslateListener()
        }
        .onDisappear {
            removeKeyboardShortcuts()
            removeQuickTranslateListener()
        }
        .alert("Ошибка", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
            print("📥 QuickTranslateText notification received in CompactContentView")
            
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
