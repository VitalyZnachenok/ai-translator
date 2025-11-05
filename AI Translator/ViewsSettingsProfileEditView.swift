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
    @State private var maxTokens = 1024
    @State private var icon = "🌐"
    
    @State private var isTestingConnection = false
    @State private var testResult = ""
    
    @StateObject private var modelService = ModelService()
    @State private var availableModels: [OpenWebUIModel] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String = ""
    @State private var canLoadModels = false
    @State private var useManualModel = false
    @State private var manualModelName = ""
    
    @Environment(\.dismiss) private var dismiss
    
    private let availableIcons = ["🌐", "🔗", "🛜", "⚡", "🚀", "💻", "🖥️", "📡", "🌟", "💎", "🔥", "⚙️"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
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
                        let finalModelName = useManualModel ? manualModelName.trimmingCharacters(in: .whitespacesAndNewlines) : modelName
                        
                        let newProfile = ConnectionProfile(
                            id: profile?.id ?? UUID().uuidString,
                            name: name,
                            apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                            apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines),
                            modelName: finalModelName,
                            temperature: temperature,
                            maxTokens: maxTokens,
                            icon: icon
                        )
                        onSave(newProfile)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || apiUrl.isEmpty || apiToken.isEmpty || 
                             (useManualModel ? manualModelName.isEmpty : modelName.isEmpty))
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Основная информация
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
                    
                    // Настройки подключения
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
                    
                    // Выбор модели
                    GroupBox(label: Label("Выбор модели", systemImage: "brain")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button(action: {
                                    if canLoadModels {
                                        loadModels()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if isLoadingModels {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .progressViewStyle(CircularProgressViewStyle())
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text(isLoadingModels ? "Загружаем..." : "Обновить список")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canLoadModels || isLoadingModels)
                                
                                Button(action: {
                                    clearModelsCache()
                                }) {
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
                            
                            if !canLoadModels {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.orange)
                                    Text("Заполните URL API и токен для загрузки моделей")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            if !modelsError.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.red)
                                    Text(modelsError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
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
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(selectedModel.providerIcon)
                                                    .font(.title3)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Выбранная модель: \(selectedModel.displayName)")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                    if let owner = selectedModel.owned_by {
                                                        Text("Провайдер: \(owner)")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text("ID модели: \(selectedModel.id)")
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
                                }
                            } else {
                                HStack {
                                    Text("Модель:")
                                        .frame(width: 100, alignment: .leading)
                                    TextField("gpt-4o-mini или llama3.2:latest", text: $modelName)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // Параметры генерации
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
                        }
                        .padding()
                    }
                    
                    // Тестирование
                    GroupBox(label: Label("Тестирование", systemImage: "testtube.2")) {
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
                                    Text(isTestingConnection ? "Тестируем..." : "Тест подключения")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiUrl.isEmpty || apiToken.isEmpty || 
                                     (useManualModel ? manualModelName.isEmpty : modelName.isEmpty) || 
                                     isTestingConnection)
                            
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
                .padding()
            }
        }
        .frame(width: 650, height: 750)
        .onAppear {
            if let profile = profile {
                name = profile.name
                apiUrl = profile.apiUrl
                apiToken = profile.apiToken
                modelName = profile.modelName
                temperature = profile.temperature
                maxTokens = profile.maxTokens
                icon = profile.icon
                manualModelName = profile.modelName
            } else {
                name = "Новый профиль"
                temperature = 0.3
                maxTokens = 1024
                icon = "🌐"
            }
            
            updateCanLoadModels()
            
            if canLoadModels {
                loadModels()
            }
        }
    }
    
    // MARK: - Private Methods
    
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
        
        let cacheKey = "cached_models_\(apiUrl)_\(apiToken.prefix(10))"
        
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cachedModels = try? JSONDecoder().decode([OpenWebUIModel].self, from: cachedData),
           !cachedModels.isEmpty {
            
            availableModels = cachedModels
            
            Task {
                await loadModelsFromAPI(cacheKey: cacheKey)
            }
            return
        }
        
        isLoadingModels = true
        modelsError = ""
        
        Task {
            await loadModelsFromAPI(cacheKey: cacheKey)
        }
    }
    
    private func loadModelsFromAPI(cacheKey: String) async {
        do {
            let models = try await modelService.fetchAvailableModels(
                apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            await MainActor.run {
                self.availableModels = models
                self.isLoadingModels = false
                
                if let encodedModels = try? JSONEncoder().encode(models) {
                    UserDefaults.standard.set(encodedModels, forKey: cacheKey)
                }
                
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
            maxTokens: maxTokens
        )
        
        tempSettings.connectionProfiles = [tempProfile]
        tempSettings.activeProfileId = tempProfile.id
        
        let testService = TranslationService()
        testService.configure(with: tempSettings)
        
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
    
    private func clearModelsCache() {
        let cacheKey = "cached_models_\(apiUrl)_\(apiToken.prefix(10))"
        UserDefaults.standard.removeObject(forKey: cacheKey)
        availableModels = []
        
        if canLoadModels {
            isLoadingModels = true
            Task {
                await loadModelsFromAPI(cacheKey: cacheKey)
            }
        }
    }
}
