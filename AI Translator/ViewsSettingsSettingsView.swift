//
//  SettingsView.swift
//  AI Translator
//
//  Окно настроек приложения
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    let onClose: (() -> Void)?
    
    @State private var selectedTab = 0
    @State private var customPrompts: [TranslationPrompt] = []
    @State private var showingAddPrompt = false
    @State private var editingPrompt: TranslationPrompt?
    @State private var showingAddProfile = false
    @State private var editingProfile: ConnectionProfile?
    @State private var quickTranslateHotkey = "⌘⇧T"
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var isTestingConnection = false
    @State private var testResult = ""
    @State private var showAdvancedSettings = false
    
    init(settingsManager: SettingsManager, onClose: (() -> Void)? = nil) {
        self.settingsManager = settingsManager
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            HStack {
                Text("Настройки AI Переводчика")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Отмена") {
                        loadSettings()
                        onClose?() ?? dismiss()
                    }
                    .keyboardShortcut(.escape)
                    
                    Button("Сохранить") {
                        saveSettings()
                        onClose?() ?? dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            TabView(selection: $selectedTab) {
                // Вкладка 1: Профили
                ScrollView {
                    VStack(spacing: 20) {
                        profilesSection
                        connectionSettings
                        testingSection
                        helpSection
                    }
                    .padding()
                }
                .tabItem {
                    Label("Подключение", systemImage: "network")
                }
                .tag(0)
                
                // Вкладка 2: Промпты
                VStack {
                    promptsSettings
                }
                .tabItem {
                    Label("Стили перевода", systemImage: "text.bubble")
                }
                .tag(1)
                
                // Вкладка 3: Горячие клавиши
                ScrollView {
                    VStack(spacing: 20) {
                        hotkeySettings
                    }
                    .padding()
                }
                .tabItem {
                    Label("Горячие клавиши", systemImage: "keyboard")
                }
                .tag(2)
            }
        }
        .frame(width: 650, height: 750)
        .onAppear {
            loadSettings()
        }
        .sheet(isPresented: $showingAddPrompt) {
            PromptEditView(prompt: nil) { newPrompt in
                customPrompts.append(newPrompt)
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditView(prompt: prompt) { updatedPrompt in
                if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
                    customPrompts[index] = updatedPrompt
                }
            }
        }
        .sheet(isPresented: $showingAddProfile) {
            ProfileEditView(profile: nil, settingsManager: settingsManager) { newProfile in
                settingsManager.addProfile(newProfile)
                loadSettingsFromActiveProfile()
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditView(profile: profile, settingsManager: settingsManager) { updatedProfile in
                settingsManager.updateProfile(updatedProfile)
                loadSettingsFromActiveProfile()
            }
        }
    }
    
    // MARK: - Profile Section
    
    private var profilesSection: some View {
        GroupBox(label: Label("📁 Профили подключения", systemImage: "folder")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Активный профиль:")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: { showingAddProfile = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Новый профиль")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                if settingsManager.connectionProfiles.isEmpty {
                    VStack(spacing: 8) {
                        Text("Нет настроенных профилей")
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button("Создать первый профиль") {
                                showingAddProfile = true
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Добавить примеры") {
                                let examples = settingsManager.createExampleProfiles()
                                for example in examples {
                                    settingsManager.addProfile(example)
                                }
                                if let first = examples.first {
                                    settingsManager.setActiveProfile(first.id)
                                    loadSettingsFromActiveProfile()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                        ForEach(settingsManager.connectionProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: settingsManager.activeProfileId == profile.id,
                                onSelect: {
                                    settingsManager.setActiveProfile(profile.id)
                                    loadSettingsFromActiveProfile()
                                },
                                onEdit: { editingProfile = profile },
                                onDuplicate: {
                                    let newProfile = settingsManager.duplicateProfile(profile)
                                    settingsManager.setActiveProfile(newProfile.id)
                                    loadSettingsFromActiveProfile()
                                },
                                onDelete: {
                                    settingsManager.deleteProfile(profile)
                                    loadSettingsFromActiveProfile()
                                }
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Connection Settings
    
    private var connectionSettings: some View {
        GroupBox(label: Label("🔗 Активный профиль", systemImage: "network")) {
            VStack(alignment: .leading, spacing: 12) {
                if let activeProfile = settingsManager.activeProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(activeProfile.icon)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activeProfile.name)
                                    .font(.headline)
                                Text("API: \(activeProfile.apiUrl)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Text("Модель: \(activeProfile.modelName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            HStack {
                                Circle()
                                    .fill(activeProfile.isConfigured ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(activeProfile.isConfigured ? "Готов" : "Не настроен")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Параметры генерации:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Temperature: \(String(format: "%.1f", activeProfile.temperature))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Max Tokens: \(activeProfile.maxTokens)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Для изменения настроек используйте редактор профилей выше")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .italic()
                    }
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Профиль не выбран")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Создайте или выберите профиль подключения выше")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .padding()
        }
    }
    
    // MARK: - Testing Section
    
    private var testingSection: some View {
        GroupBox(label: Label("🧪 Тестирование", systemImage: "testtube.2")) {
            VStack(spacing: 12) {
                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTestingConnection ? "Тестируем подключение..." : "Тест активного профиля")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(settingsManager.activeProfile == nil || !settingsManager.isConfigured || isTestingConnection)
                
                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.caption)
                        .foregroundColor(testResult.contains("✅") ? .green : .red)
                        .multilineTextAlignment(.center)
                }
                
                if settingsManager.activeProfile == nil {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Создайте или выберите профиль для тестирования")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        DisclosureGroup("ℹ️ Как получить настройки", isExpanded: $showAdvancedSettings) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Для получения API ключа:")
                    .font(.headline)
                
                ForEach(Array(instructionSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                        Text(step)
                            .font(.caption)
                    }
                }
                
                Divider()
                
                Text("Примеры URL:")
                    .font(.headline)
                Text("• https://your-domain.com/v1")
                    .font(.system(.caption, design: .monospaced))
                Text("• http://localhost:3000/v1")
                    .font(.system(.caption, design: .monospaced))
            }
            .padding()
        }
        .padding(.horizontal)
    }
    
    private let instructionSteps = [
        "Откройте ваш OpenWebUI",
        "Перейдите в Settings → Account → API Keys",
        "Нажмите 'Create new API key'",
        "Скопируйте созданный ключ",
        "URL обычно имеет вид: https://your-domain.com/v1",
        "Нажмите 'Обновить' для загрузки списка доступных моделей"
    ]
    
    // MARK: - Prompts Settings
    
    private var promptsSettings: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Настройка стилей перевода")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingAddPrompt = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Добавить стиль")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            if customPrompts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Нет настроенных стилей")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Добавьте свои стили перевода для разных случаев:\nпростой язык, технический перевод, литературный стиль и т.д.")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: addDefaultPrompts) {
                        Label("Добавить примеры стилей", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(customPrompts) { prompt in
                        HStack {
                            Text(prompt.icon)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prompt.name)
                                    .font(.headline)
                                Text(prompt.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            Button(action: { editingPrompt = prompt }) {
                                Image(systemName: "pencil.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: { deletePrompt(prompt) }) {
                                Image(systemName: "trash.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Hotkey Settings
    
    private var hotkeySettings: some View {
        VStack(spacing: 20) {
            GroupBox(label: Label("⚡ Быстрый перевод", systemImage: "keyboard")) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Горячая клавиша для быстрого перевода из буфера обмена")
                        .font(.headline)
                    
                    HStack {
                        Text("Текущая комбинация:")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { startRecordingHotkey() }) {
                            HStack {
                                if isRecordingHotkey {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Text("Нажмите новую комбинацию...")
                                        .foregroundColor(.orange)
                                } else {
                                    Text(quickTranslateHotkey)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isRecordingHotkey ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if isRecordingHotkey {
                            Button("Отмена") {
                                stopRecordingHotkey()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Изменить") {
                                startRecordingHotkey()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Text("Используйте модификаторы: ⌘ Command, ⇧ Shift, ⌥ Option, ⌃ Control")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Button("Сбросить на значение по умолчанию (⌘⇧T)") {
                        quickTranslateHotkey = "⌘⇧T"
                        settingsManager.quickTranslateHotkey = quickTranslateHotkey
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                .padding()
            }
            
            GroupBox(label: Label("📋 Как использовать", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Быстрый перевод выделенного текста:")
                        .font(.headline)
                    
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("Выделите текст в любом приложении")
                            .font(.caption)
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("Нажмите горячую клавишу \(quickTranslateHotkey)")
                            .font(.caption)
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("Переводчик автоматически скопирует выделенный текст и начнет перевод")
                            .font(.caption)
                    }
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Приложение автоматически восстановит предыдущее содержимое буфера обмена")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSettings() {
        loadSettingsFromActiveProfile()
        customPrompts = settingsManager.customPrompts
        quickTranslateHotkey = settingsManager.quickTranslateHotkey
    }
    
    private func loadSettingsFromActiveProfile() {
        // Профили управляются через settingsManager
    }
    
    private func saveSettings() {
        settingsManager.customPrompts = customPrompts
        
        let hotkeyChanged = settingsManager.quickTranslateHotkey != quickTranslateHotkey
        settingsManager.quickTranslateHotkey = quickTranslateHotkey
        
        settingsManager.saveSettings()
        
        if hotkeyChanged {
            NotificationCenter.default.post(name: Notification.Name("HotkeyChanged"), object: nil)
        }
    }
    
    private func deletePrompt(_ prompt: TranslationPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
    }
    
    private func addDefaultPrompts() {
        customPrompts = [
            TranslationPrompt(
                name: "Простой язык",
                description: "Использует простые слова и короткие предложения",
                icon: "💬",
                systemPrompt: "Переводи текст, используя максимально простой и понятный язык. Избегай сложных терминов и длинных предложений. Делай текст доступным для широкой аудитории.",
                userPromptAddition: "Используй простые слова и короткие предложения."
            ),
            TranslationPrompt(
                name: "Технический",
                description: "Точный перевод технических терминов",
                icon: "⚙️",
                systemPrompt: "Ты технический переводчик. Сохраняй точность технических терминов и специальной терминологии. Не упрощай технические концепции.",
                userPromptAddition: "Сохрани все технические термины точными."
            ),
            TranslationPrompt(
                name: "Литературный",
                description: "Художественный и выразительный перевод",
                icon: "📚",
                systemPrompt: "Ты литературный переводчик. Создавай красивый, выразительный перевод с сохранением стилистики и эмоциональной окраски оригинала.",
                userPromptAddition: "Сделай перевод литературным и выразительным."
            ),
            TranslationPrompt(
                name: "Деловой",
                description: "Формальный и профессиональный стиль",
                icon: "💼",
                systemPrompt: "Переводи в формальном деловом стиле. Используй профессиональную лексику и соблюдай деловой этикет.",
                userPromptAddition: "Используй формальный деловой стиль."
            )
        ]
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = ""
        
        let testService = TranslationService()
        testService.configure(with: settingsManager)
        
        Task {
            do {
                let result = try await testService.translate(
                    text: "Hello world",
                    from: "en",
                    to: "ru",
                    customPrompt: nil
                )
                
                await MainActor.run {
                    testResult = "✅ Подключение успешно!\nТестовый перевод: \(result)"
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Ошибка: \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }
    
    private func startRecordingHotkey() {
        isRecordingHotkey = true
        
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isRecordingHotkey else { return event }
            
            var modifiers: [String] = []
            
            if event.modifierFlags.contains(.control) {
                modifiers.append("⌃")
            }
            if event.modifierFlags.contains(.option) {
                modifiers.append("⌥")
            }
            if event.modifierFlags.contains(.shift) {
                modifiers.append("⇧")
            }
            if event.modifierFlags.contains(.command) {
                modifiers.append("⌘")
            }
            
            if !modifiers.isEmpty {
                let keyChar = KeyCodeMapper.characterForKeyCode(event.keyCode)
                self.quickTranslateHotkey = modifiers.joined() + keyChar
                self.settingsManager.quickTranslateHotkey = self.quickTranslateHotkey
                self.stopRecordingHotkey()
                return nil
            }
            
            return event
        }
    }
    
    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }
}
