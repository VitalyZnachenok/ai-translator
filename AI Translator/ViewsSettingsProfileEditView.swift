//
//  ProfileEditView.swift
//  AI Translator
//
//  Редактор профилей подключения к API
//

import SwiftUI

struct ProfileEditView: View {
    let profile: ConnectionProfile?
    let settingsManager: SettingsManager
    let onSave: (ConnectionProfile) -> Void
    
    @State private var name = ""
    @State private var apiUrl = ""
    @State private var apiToken = ""
    @State private var modelName = ""
    @State private var temperature = 0.3
    @State private var maxTokens = 2048
    @State private var icon = "🌐"
    @State private var reasoningEffort: ReasoningEffort = .serverDefault
    
    @State private var isTestingConnection = false
    @State private var testResult = ""
    
    @State private var availableModels: [OpenWebUIModel] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String = ""
    @State private var canLoadModels = false
    @State private var useManualModel = false
    @State private var manualModelName = ""
    /// Стабильный идентификатор профиля: для существующего — его id, для нового — заранее сгенерированный.
    @State private var profileId = UUID().uuidString
    
    @Environment(\.dismiss) private var dismiss
    
    private let modelService = ModelService()
    private let availableIcons = ["🌐", "🔗", "🛜", "⚡", "🚀", "💻", "🖥️", "📡", "🌟", "💎", "🔥", "⚙️"]
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    basicInfoSection
                    connectionSection
                    modelSelectionSection
                    generationParamsSection
                    testingSection
                }
                .padding()
            }
        }
        .frame(width: 650, height: 750)
        .onAppear {
            initializeForm()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text(profile == nil ? "Новый профиль подключения" : "Редактировать профиль")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Сохранить") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var canSave: Bool {
        !name.isEmpty && !apiUrl.isEmpty && !apiToken.isEmpty &&
        (useManualModel ? !manualModelName.isEmpty : !modelName.isEmpty)
    }
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        GroupBox(label: Label("Основная информация", systemImage: "info.circle")) {
            VStack(spacing: 12) {
                HStack {
                    Text("Иконка:")
                        .frame(width: 100, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableIcons, id: \.self) { emoji in
                                Button(action: { icon = emoji }) {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(icon == emoji ? Color.blue.opacity(0.2) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(icon == emoji ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 50)
                }
                
                HStack {
                    Text("Название:")
                        .frame(width: 100, alignment: .leading)
                    TextField("Например: 'Основной сервер'", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        GroupBox(label: Label("Настройки подключения", systemImage: "network")) {
            VStack(spacing: 12) {
                HStack {
                    Text("URL API:")
                        .frame(width: 100, alignment: .leading)
                    TextField("https://your-openwebui.com/v1", text: $apiUrl)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiUrl) { _, _ in updateCanLoadModels() }
                }
                
                HStack {
                    Text("API Token:")
                        .frame(width: 100, alignment: .leading)
                    SecureField("Введите токен", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiToken) { _, _ in updateCanLoadModels() }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Model Selection Section
    
    private var modelSelectionSection: some View {
        GroupBox(label: Label("Выбор модели", systemImage: "brain")) {
            VStack(alignment: .leading, spacing: 12) {
                modelControlButtons
                
                if !canLoadModels {
                    warningMessage("Заполните URL API и токен для загрузки моделей", color: .orange)
                }
                
                if !modelsError.isEmpty {
                    warningMessage(modelsError, color: .red, icon: "exclamationmark.triangle")
                }
                
                modelInputSection
            }
            .padding()
        }
    }
    
    private var modelControlButtons: some View {
        HStack {
            Button(action: loadModels) {
                HStack(spacing: 4) {
                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.mini)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isLoadingModels ? "Загружаем..." : "Обновить список")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(!canLoadModels || isLoadingModels)
            
            Button(action: clearModelsCache) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Очистить кэш")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Очистить кэш моделей и загрузить заново")
            
            Spacer()
            
            Toggle(isOn: $useManualModel) {
                Text("Ручной ввод")
                    .font(.caption)
            }
            .toggleStyle(SwitchToggleStyle())
        }
    }
    
    @ViewBuilder
    private var modelInputSection: some View {
        if useManualModel {
            HStack {
                Text("Модель:")
                    .frame(width: 100, alignment: .leading)
                TextField("gpt-4o-mini или llama3.2:latest", text: $manualModelName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: manualModelName) { _, newValue in
                        modelName = newValue
                    }
            }
        } else if !availableModels.isEmpty {
            modelPickerSection
        } else {
            HStack {
                Text("Модель:")
                    .frame(width: 100, alignment: .leading)
                TextField("gpt-4o-mini или llama3.2:latest", text: $modelName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Модель:")
                    .frame(width: 100, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Выберите модель", selection: $modelName) {
                        Text("Выберите модель...")
                            .tag("")
                        
                        ForEach(availableModels) { model in
                            Text("\(model.providerIcon) \(model.displayName)")
                                .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Доступно моделей: \(availableModels.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if let selectedModel = availableModels.first(where: { $0.id == modelName }) {
                selectedModelInfo(selectedModel)
            }
        }
    }
    
    private func selectedModelInfo(_ model: OpenWebUIModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.providerIcon)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выбранная модель: \(model.displayName)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    if let owner = model.owned_by {
                        Text("Провайдер: \(owner)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("ID модели: \(model.id)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }
    
    private func warningMessage(_ text: String, color: Color, icon: String = "info.circle") -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(color)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Generation Params Section
    
    private var generationParamsSection: some View {
        GroupBox(label: Label("Параметры генерации", systemImage: "slider.horizontal.3")) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature:")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens:")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                        Text("\(maxTokens)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 60, alignment: .trailing)
                    }
                    Slider(value: Binding(
                        get: { Double(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 256...4096, step: 256)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Мышление:")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $reasoningEffort) {
                            ForEach(ReasoningEffort.allCases) { effort in
                                Text(effort.displayName).tag(effort)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Text("Для «думающих» моделей. «Выключено» отключает рассуждения (Ollama: reasoning_effort=none). «По умолчанию» — параметр не отправляется.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Testing Section
    
    private var testingSection: some View {
        GroupBox(label: Label("Тестирование", systemImage: "testtube.2")) {
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
                        Text(isTestingConnection ? "Тестируем..." : "Тест подключения")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canTest)
                
                if !testResult.isEmpty {
                    ScrollView {
                        Text(testResult)
                            .font(.caption)
                            .foregroundColor(testResult.contains("✅") ? .green : .red)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
    }
    
    private var canTest: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty &&
        (useManualModel ? !manualModelName.isEmpty : !modelName.isEmpty) &&
        !isTestingConnection
    }
    
    // MARK: - Actions
    
    private func initializeForm() {
        if let profile {
            profileId = profile.id
            name = profile.name
            apiUrl = profile.apiUrl
            apiToken = profile.apiToken
            modelName = profile.modelName
            temperature = profile.temperature
            maxTokens = profile.maxTokens
            icon = profile.icon
            reasoningEffort = profile.reasoningEffort
            manualModelName = profile.modelName
        } else {
            name = "Новый профиль"
            temperature = 0.3
            maxTokens = 2048
            icon = "🌐"
        }
        
        updateCanLoadModels()
        
        if canLoadModels {
            loadModels()
        }
    }
    
    private func saveProfile() {
        let finalModelName = useManualModel ? manualModelName.trimmingCharacters(in: .whitespacesAndNewlines) : modelName
        
        let newProfile = ConnectionProfile(
            id: profileId,
            name: name,
            apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: finalModelName,
            temperature: temperature,
            maxTokens: maxTokens,
            icon: icon,
            reasoningEffort: reasoningEffort
        )
        onSave(newProfile)
        dismiss()
    }
    
    private func updateCanLoadModels() {
        let newCanLoad = !apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if canLoadModels != newCanLoad {
            canLoadModels = newCanLoad
            modelsError = ""
            if newCanLoad && !isLoadingModels {
                availableModels = []
            }
        }
    }
    
    private func loadModels() {
        guard canLoadModels else { return }

        if let cachedModels = ModelsCache.load(for: profileId) {
            availableModels = cachedModels

            Task {
                await loadModelsFromAPI()
            }
            return
        }
        
        isLoadingModels = true
        modelsError = ""
        
        Task {
            await loadModelsFromAPI()
        }
    }
    
    private func loadModelsFromAPI() async {
        do {
            let models = try await modelService.fetchAvailableModels(
                apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            await MainActor.run {
                self.availableModels = models
                self.isLoadingModels = false

                ModelsCache.save(models, for: profileId)
                
                if !modelName.isEmpty && !models.contains(where: { $0.id == modelName }) {
                    useManualModel = true
                    manualModelName = modelName
                }
                
                if !useManualModel && modelName.isEmpty && !models.isEmpty {
                    let preferredModel = models.first { model in
                        let name = model.displayName.lowercased()
                        return name.contains("gpt-4") || name.contains("llama") || name.contains("mistral")
                    } ?? models.first!
                    
                    modelName = preferredModel.id
                }
            }
        } catch {
            await MainActor.run {
                self.modelsError = "Ошибка загрузки: \(error.localizedDescription)"
                self.isLoadingModels = false
                
                if !useManualModel {
                    useManualModel = true
                    manualModelName = modelName
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = ""
        
        let finalModelName = useManualModel ? manualModelName.trimmingCharacters(in: .whitespacesAndNewlines) : modelName
        
        let tempSettings = SettingsManager()
        let tempProfile = ConnectionProfile(
            name: "Test",
            apiUrl: apiUrl,
            apiToken: apiToken,
            modelName: finalModelName,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: reasoningEffort
        )
        
        tempSettings.connectionProfiles = [tempProfile]
        tempSettings.activeProfileId = tempProfile.id
        
        let testService = TranslationService()
        
        Task {
            await testService.configure(with: tempSettings)
            
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
    
    private func clearModelsCache() {
        ModelsCache.clear(for: profileId)
        availableModels = []
        
        if canLoadModels {
            isLoadingModels = true
            Task {
                await loadModelsFromAPI()
            }
        }
    }
}
