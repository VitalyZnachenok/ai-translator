//
//  SettingsView.swift
//  AI Translator
//
//  Окно настроек приложения
//

import SwiftUI

struct SettingsView: View {
    var settingsManager: SettingsManager
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
    @State private var recordingTarget: HotkeyTarget = .quick

    // In-place translation
    @State private var inPlaceEnabled = true
    @State private var inPlaceTranslateHotkey = "⌘⇧T"
    @State private var inPlaceUseCustomSettings = false
    @State private var inPlaceSourceLanguage = "auto"
    @State private var inPlaceTargetLanguage = "ru"
    @State private var inPlacePromptId = ""
    @State private var inPlaceAutoSwap = false
    @State private var inPlaceLanguagePairs: [LanguagePair] = []

    @State private var isTestingConnection = false
    @State private var testResult = ""
    @State private var showAdvancedSettings = false

    private enum HotkeyTarget {
        case quick
        case inPlace
    }
    
    init(settingsManager: SettingsManager, onClose: (() -> Void)? = nil) {
        self.settingsManager = settingsManager
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabContent
        }
        .frame(width: 650, height: 750)
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            stopRecordingHotkey()
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
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("Настройки AI Переводчика")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Отмена") {
                    loadSettings()
                    closeView()
                }
                .keyboardShortcut(.escape)
                
                Button("Сохранить") {
                    saveSettings()
                    closeView()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var tabContent: some View {
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
                    emptyProfilesView
                } else {
                    profilesGrid
                }
            }
            .padding()
        }
    }
    
    private var emptyProfilesView: some View {
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
    }
    
    private var profilesGrid: some View {
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
    
    // MARK: - Connection Settings
    
    private var connectionSettings: some View {
        GroupBox(label: Label("🔗 Активный профиль", systemImage: "network")) {
            VStack(alignment: .leading, spacing: 12) {
                if let activeProfile = settingsManager.activeProfile {
                    activeProfileInfo(activeProfile)
                } else {
                    noActiveProfileView
                }
            }
            .padding()
        }
    }
    
    private func activeProfileInfo(_ profile: ConnectionProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                    Text("API: \(profile.apiUrl)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("Модель: \(profile.modelName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                
                HStack {
                    Circle()
                        .fill(profile.isConfigured ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(profile.isConfigured ? "Готов" : "Не настроен")
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
                Text("Temperature: \(String(format: "%.1f", profile.temperature))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text("Max Tokens: \(profile.maxTokens)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Для изменения настроек используйте редактор профилей выше")
                .font(.caption)
                .foregroundColor(.blue)
                .italic()
        }
    }
    
    private var noActiveProfileView: some View {
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
    
    // MARK: - Testing Section
    
    private var testingSection: some View {
        GroupBox(label: Label("🧪 Тестирование", systemImage: "testtube.2")) {
            VStack(spacing: 12) {
                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
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
                emptyPromptsView
            } else {
                promptsList
            }
        }
    }
    
    private var emptyPromptsView: some View {
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
    }
    
    private var promptsList: some View {
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
    
    // MARK: - Hotkey Settings

    private var hotkeySettings: some View {
        VStack(spacing: 20) {
            quickTranslateSection
            inPlaceTranslateSection
            hotkeyInstructions
            Spacer()
        }
    }

    private var quickTranslateSection: some View {
        GroupBox(label: Label("⚡ Быстрый перевод (в окне)", systemImage: "keyboard")) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Открыть окно переводчика и сразу перевести выделенный текст")
                    .font(.headline)

                HStack {
                    Text("Текущая комбинация:")
                        .foregroundColor(.secondary)

                    Spacer()

                    hotkeyDisplay(value: quickTranslateHotkey, target: .quick)
                    hotkeyEditButton(target: .quick)
                }

                Text("Используйте модификаторы: ⌘ Command, ⇧ Shift, ⌥ Option, ⌃ Control")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Button("Сбросить на значение по умолчанию (⌘⇧T)") {
                    quickTranslateHotkey = "⌘⇧T"
                    settingsManager.quickTranslateHotkey = quickTranslateHotkey
                }
                .buttonStyle(UnderlinedLinkButtonStyle())
            }
            .padding()
        }
    }

    private var inPlaceTranslateSection: some View {
        GroupBox(label: Label("↪︎ Перевод на месте", systemImage: "arrow.triangle.2.circlepath")) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $inPlaceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Включить перевод на месте")
                            .font(.headline)
                        Text("Заменяет выделенный текст переводом прямо в активном окне")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if inPlaceEnabled {
                    Divider()

                    HStack {
                        Text("Горячая клавиша:")
                            .foregroundColor(.secondary)

                        Spacer()

                        hotkeyDisplay(value: inPlaceTranslateHotkey, target: .inPlace)
                        hotkeyEditButton(target: .inPlace)
                    }

                    if hotkeyConflict {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Конфликт: эта комбинация совпадает с быстрым переводом — приоритет получит перевод на месте.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Divider()

                    Toggle(isOn: $inPlaceUseCustomSettings) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Использовать собственные настройки")
                                .font(.subheadline)
                            Text(inPlaceUseCustomSettings
                                 ? "Перевод на месте использует язык и стиль, заданные ниже"
                                 : "Перевод на месте использует язык и стиль, выбранные в окне переводчика")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if inPlaceUseCustomSettings {
                        inPlaceCustomSettings
                    }

                    Divider()

                    autoSwapSettings
                }
            }
            .padding()
        }
    }

    private var autoSwapSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $inPlaceAutoSwap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автоматический обмен по определению языка")
                        .font(.subheadline)
                    Text("Определяет язык выделенного текста и переводит в обратную сторону пары. Если язык не входит ни в одну активную пару — используются настройки выше.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if inPlaceAutoSwap {
                languagePairsEditor
            }
        }
    }

    private var languagePairsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Языковые пары")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    inPlaceLanguagePairs.append(LanguagePair(primary: "ru", secondary: "en"))
                } label: {
                    Label("Добавить пару", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if inPlaceLanguagePairs.isEmpty {
                Text("Список пар пуст — добавьте хотя бы одну, чтобы автообмен заработал.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                ForEach($inPlaceLanguagePairs) { $pair in
                    languagePairRow(pair: $pair)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func languagePairRow(pair: Binding<LanguagePair>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: pair.enabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Picker("", selection: pair.primary) {
                ForEach(LanguageData.fullLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)

            Image(systemName: "arrow.left.arrow.right")
                .foregroundColor(.secondary)

            Picker("", selection: pair.secondary) {
                ForEach(LanguageData.fullLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)

            Spacer()

            Button {
                inPlaceLanguagePairs.removeAll { $0.id == pair.wrappedValue.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Удалить пару")
        }
        .padding(.vertical, 2)
    }

    private var inPlaceCustomSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Исходный язык:")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: $inPlaceSourceLanguage) {
                    ForEach(LanguageData.fullLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Целевой язык:")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: $inPlaceTargetLanguage) {
                    ForEach(LanguageData.fullLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Стиль перевода:")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: $inPlacePromptId) {
                    Text("По умолчанию").tag("")
                    ForEach(customPrompts) { prompt in
                        Text("\(prompt.icon) \(prompt.name)").tag(prompt.id)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(.leading, 4)
    }

    private var hotkeyConflict: Bool {
        inPlaceEnabled && inPlaceTranslateHotkey == quickTranslateHotkey
    }

    private func hotkeyDisplay(value: String, target: HotkeyTarget) -> some View {
        let isActive = isRecordingHotkey && recordingTarget == target
        return Button(action: { startRecordingHotkey(for: target) }) {
            HStack {
                if isActive {
                    ProgressView()
                        .controlSize(.mini)
                        .progressViewStyle(.circular)
                    Text("Нажмите новую комбинацию...")
                        .foregroundColor(.orange)
                } else {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func hotkeyEditButton(target: HotkeyTarget) -> some View {
        let isActive = isRecordingHotkey && recordingTarget == target
        if isActive {
            Button("Отмена") { stopRecordingHotkey() }
                .buttonStyle(.bordered)
        } else {
            Button("Изменить") { startRecordingHotkey(for: target) }
                .buttonStyle(.bordered)
        }
    }

    private var hotkeyInstructions: some View {
        GroupBox(label: Label("📋 Как использовать", systemImage: "info.circle")) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Быстрый перевод выделенного текста (в окне):")
                        .font(.headline)

                    instructionRow(number: "1.", text: "Выделите текст в любом приложении")
                    instructionRow(number: "2.", text: "Нажмите горячую клавишу \(quickTranslateHotkey)")
                    instructionRow(number: "3.", text: "Откроется окно переводчика с готовым переводом")
                }

                if inPlaceEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Перевод на месте (с заменой текста):")
                            .font(.headline)

                        instructionRow(number: "1.", text: "Выделите текст в любом приложении")
                        instructionRow(number: "2.", text: "Нажмите горячую клавишу \(inPlaceTranslateHotkey)")
                        instructionRow(number: "3.", text: "Выделенный текст будет заменён переводом прямо на месте")
                        instructionRow(number: "4.", text: "Повторное нажатие \(inPlaceTranslateHotkey) во время перевода отменяет операцию")
                    }

                    if inPlaceAutoSwap {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Автоматический обмен направлением:")
                                .font(.subheadline.weight(.semibold))
                            Text("Приложение само определит язык выделенного текста и переведёт его в обратную сторону пары — например, русский ↔ английский. Если язык не входит ни в одну активную пару, используется обычное направление перевода.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider()

                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Приложение автоматически восстанавливает предыдущее содержимое буфера обмена")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
            Text(text)
                .font(.caption)
        }
    }
    
    // MARK: - Private Methods
    
    private func closeView() {
        onClose?() ?? dismiss()
    }
    
    private func loadSettings() {
        loadSettingsFromActiveProfile()
        customPrompts = settingsManager.customPrompts
        quickTranslateHotkey = settingsManager.quickTranslateHotkey

        inPlaceEnabled = settingsManager.inPlaceEnabled
        inPlaceTranslateHotkey = settingsManager.inPlaceTranslateHotkey
        inPlaceUseCustomSettings = settingsManager.inPlaceUseCustomSettings
        inPlaceSourceLanguage = settingsManager.inPlaceSourceLanguage
        inPlaceTargetLanguage = settingsManager.inPlaceTargetLanguage
        inPlacePromptId = settingsManager.inPlacePromptId
        inPlaceAutoSwap = settingsManager.inPlaceAutoSwap
        inPlaceLanguagePairs = settingsManager.inPlaceLanguagePairs
    }
    
    private func loadSettingsFromActiveProfile() {
        // Профили управляются через settingsManager
    }
    
    private func saveSettings() {
        settingsManager.customPrompts = customPrompts

        let quickChanged = settingsManager.quickTranslateHotkey != quickTranslateHotkey
        let inPlaceChanged =
            settingsManager.inPlaceTranslateHotkey != inPlaceTranslateHotkey
            || settingsManager.inPlaceEnabled != inPlaceEnabled

        settingsManager.quickTranslateHotkey = quickTranslateHotkey

        settingsManager.inPlaceEnabled = inPlaceEnabled
        settingsManager.inPlaceTranslateHotkey = inPlaceTranslateHotkey
        settingsManager.inPlaceUseCustomSettings = inPlaceUseCustomSettings
        settingsManager.inPlaceSourceLanguage = inPlaceSourceLanguage
        settingsManager.inPlaceTargetLanguage = inPlaceTargetLanguage
        settingsManager.inPlacePromptId = inPlacePromptId
        settingsManager.inPlaceAutoSwap = inPlaceAutoSwap
        settingsManager.inPlaceLanguagePairs = inPlaceLanguagePairs

        settingsManager.saveSettings()

        if quickChanged || inPlaceChanged {
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
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
        
        Task {
            await testService.configure(with: settingsManager)
            
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
    
    private func startRecordingHotkey(for target: HotkeyTarget = .quick) {
        stopRecordingHotkey()
        recordingTarget = target
        isRecordingHotkey = true

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard isRecordingHotkey else { return event }

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
                let combo = modifiers.joined() + keyChar

                switch recordingTarget {
                case .quick:
                    quickTranslateHotkey = combo
                case .inPlace:
                    inPlaceTranslateHotkey = combo
                }

                stopRecordingHotkey()
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
