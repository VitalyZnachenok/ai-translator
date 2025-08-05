// MARK: - TranslatorApp.swift (Главный файл приложения)
import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate для управления меню-баром
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var sharedSettingsManager = SettingsManager() // Общий экземпляр
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "AI Переводчик")
        button.imagePosition = .imageOnly
        
        // Убираем автоматическое меню и настраиваем кастомное поведение
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        setupPopover()
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // Правый клик - показываем контекстное меню
            showContextMenu()
        } else {
            // Левый клик - показываем/скрываем popover
            togglePopover()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "🌐 Открыть переводчик", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "⚙️ Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "📖 О программе", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "❌ Выйти", action: #selector(quit), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        // Показываем меню в позиции кнопки
        guard let button = statusBarItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 450, height: 550)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: CompactContentView(settingsManager: sharedSettingsManager))
    }
    
    @objc private func togglePopover() {
        guard let button = statusBarItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.becomeKey()
            }
        }
    }
    
    @objc func showMainWindow() {
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        mainWindow.title = "AI Переводчик"
        mainWindow.contentView = NSHostingView(rootView: ContentView(settingsManager: sharedSettingsManager))
        mainWindow.center()
        mainWindow.makeKeyAndOrderFront(nil)
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Настройки"
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(settingsManager: sharedSettingsManager))
            
            // Добавляем обработчик закрытия окна
            settingsWindow?.delegate = self
        }
        
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showAbout() {
        let aboutPanel = NSAlert()
        aboutPanel.messageText = "AI Переводчик"
        aboutPanel.informativeText = """
        Версия 1.0
        
        Умный переводчик с поддержкой OpenWebUI API
        
        Возможности:
        • Перевод между 14 языками
        • Интеграция с любыми AI моделями
        • Работа из меню-бара
        • Быстрый доступ и компактный интерфейс
        
        Создано для удобного перевода текстов с помощью ИИ.
        """
        aboutPanel.addButton(withTitle: "OK")
        aboutPanel.runModal()
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Расширение для обработки закрытия окна настроек
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            settingsWindow = nil
        }
    }
}

// MARK: - ContentView.swift (Главный интерфейс)
import SwiftUI

struct ContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager // Принимаем извне
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var showingSettings = false
    @State private var selectedSourceLanguage = "auto"
    @State private var selectedTargetLanguage = "ru"
    @State private var errorMessage = ""
    @State private var showingError = false
    
    let languages = [
        ("auto", "🌐 Авто-определение"),
        ("en", "🇺🇸 English"),
        ("ru", "🇷🇺 Русский"),
        ("zh", "🇨🇳 中文"),
        ("es", "🇪🇸 Español"),
        ("fr", "🇫🇷 Français"),
        ("de", "🇩🇪 Deutsch"),
        ("ja", "🇯🇵 日本語"),
        ("ko", "🇰🇷 한국어"),
        ("it", "🇮🇹 Italiano"),
        ("pt", "🇵🇹 Português"),
        ("ar", "🇸🇦 العربية"),
        ("hi", "🇮🇳 हिन्दी"),
        ("tr", "🇹🇷 Türkçe")
    ]
    
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
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            
            // Выбор языков
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("С какого языка:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Исходный язык", selection: $selectedSourceLanguage) {
                        ForEach(languages, id: \.0) { code, name in
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
                
                VStack(alignment: .leading) {
                    Text("На какой язык:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Целевой язык", selection: $selectedTargetLanguage) {
                        ForEach(languages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 200)
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
                    .onChange(of: inputText) { newValue in
                        if newValue.count > 5000 {
                            inputText = String(newValue.prefix(5000))
                        }
                    }
            }
            .padding(.horizontal)
            
            // Кнопка перевода
            Button(action: translateText) {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle())
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
            }
            .disabled(inputText.isEmpty || isTranslating || !settingsManager.isConfigured)
            .buttonStyle(PlainButtonStyle())
            
            // Результат перевода
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Результат перевода:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !outputText.isEmpty {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Копировать")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.blue)
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
                .frame(minHeight: 120, maxHeight: 300)
            }
            .padding(.horizontal)
            
            if !settingsManager.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Настройте подключение к OpenWebUI в настройках")
                        .foregroundColor(.orange)
                }
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
        
        Task {
            do {
                let result = try await translationService.translate(
                    text: inputText,
                    from: selectedSourceLanguage,
                    to: selectedTargetLanguage
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
    }
}

// MARK: - CompactContentView (Компактный вид для popover)
struct CompactContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager // Принимаем извне
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var selectedSourceLanguage = "auto"
    @State private var selectedTargetLanguage = "ru"
    @State private var errorMessage = ""
    @State private var showingError = false
    
    let languages = [
        ("auto", "🌐 Авто"),
        ("en", "🇺🇸 EN"),
        ("ru", "🇷🇺 RU"),
        ("zh", "🇨🇳 ZH"),
        ("es", "🇪🇸 ES"),
        ("fr", "🇫🇷 FR"),
        ("de", "🇩🇪 DE"),
        ("ja", "🇯🇵 JA"),
        ("ko", "🇰🇷 KO"),
        ("it", "🇮🇹 IT"),
        ("pt", "🇵🇹 PT"),
        ("ar", "🇸🇦 AR"),
        ("hi", "🇮🇳 HI"),
        ("tr", "🇹🇷 TR")
    ]
    
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Заголовок
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                Text("AI Переводчик")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            // Выбор языков (компактный)
            HStack(spacing: 8) {
                Picker("От", selection: $selectedSourceLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 80)
                
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedSourceLanguage == "auto")
                
                Picker("В", selection: $selectedTargetLanguage) {
                    ForEach(languages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 80)
                
                Spacer()
                
                // Кнопка полной версии
                Button("🔍") {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showMainWindow()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help("Открыть полную версию")
            }
            .padding(.horizontal)
            
            // Поле ввода (компактное)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Текст:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(inputText.count)/1000")
                        .font(.caption2)
                        .foregroundColor(inputText.count > 900 ? .red : .secondary)
                }
                
                TextEditor(text: $inputText)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .frame(minHeight: 80, maxHeight: 120)
                    .onChange(of: inputText) { newValue in
                        if newValue.count > 1000 {
                            inputText = String(newValue.prefix(1000))
                        }
                    }
            }
            .padding(.horizontal)
            
            // Кнопка перевода
            Button(action: translateText) {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle())
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
            
            // Результат (компактный)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Результат:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !outputText.isEmpty {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.blue)
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
            
            // Предупреждение о настройках
            if !settingsManager.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Настройте подключение")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Настройки") {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.showSettings()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            translationService.configure(with: settingsManager)
        }
        .alert("Ошибка", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
        
        Task {
            do {
                let result = try await translationService.translate(
                    text: inputText,
                    from: selectedSourceLanguage,
                    to: selectedTargetLanguage
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
    }
}

// MARK: - SettingsView.swift (Настройки)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiUrl = ""
    @State private var apiToken = ""
    @State private var modelName = ""
    @State private var temperature = 0.3
    @State private var maxTokens = 1024
    @State private var isTestingConnection = false
    @State private var testResult = ""
    @State private var showingTestResult = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("🔗 Подключение к OpenWebUI")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL API:")
                            .font(.headline)
                        TextField("https://your-openwebui.com", text: $apiUrl)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Token:")
                            .font(.headline)
                        SecureField("Ваш API токен", text: $apiToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Модель для перевода:")
                            .font(.headline)
                        TextField("gpt-4, claude-3-sonnet, llama2 и т.д.", text: $modelName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Section(header: Text("⚙️ Параметры генерации")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Temperature: \(String(format: "%.1f", temperature))")
                            .font(.headline)
                        Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                        Text("Контролирует креативность перевода (0.0 - точный, 1.0 - творческий)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Tokens: \(maxTokens)")
                            .font(.headline)
                        Slider(value: Binding(
                            get: { Double(maxTokens) },
                            set: { maxTokens = Int($0) }
                        ), in: 256...4096, step: 256)
                        Text("Максимальная длина ответа")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("🧪 Тестирование")) {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingConnection ? "Тестируем..." : "Тест подключения")
                        }
                    }
                    .disabled(apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty || isTestingConnection)
                }
                
                Section(header: Text("ℹ️ Информация")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Как получить настройки:")
                            .font(.headline)
                        Text("1. Откройте ваш OpenWebUI")
                        Text("2. Перейдите в Settings → Account → API Keys")
                        Text("3. Создайте новый API ключ")
                        Text("4. URL обычно выглядит как: https://your-domain.com/v1")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(width: 500, height: 600)
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        loadSettings()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveSettings()
                        dismiss()
                    }
                    .disabled(apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
        .alert("Результат теста", isPresented: $showingTestResult) {
            Button("OK") { }
        } message: {
            Text(testResult)
        }
    }
    
    private func loadSettings() {
        apiUrl = settingsManager.apiUrl
        apiToken = settingsManager.apiToken
        modelName = settingsManager.modelName
        temperature = settingsManager.temperature
        maxTokens = settingsManager.maxTokens
    }
    
    private func saveSettings() {
        settingsManager.apiUrl = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.temperature = temperature
        settingsManager.maxTokens = maxTokens
        settingsManager.saveSettings()
    }
    
    private func testConnection() {
        isTestingConnection = true
        
        let tempSettings = SettingsManager()
        tempSettings.apiUrl = apiUrl
        tempSettings.apiToken = apiToken
        tempSettings.modelName = modelName
        tempSettings.temperature = temperature
        tempSettings.maxTokens = maxTokens
        
        let testService = TranslationService()
        testService.configure(with: tempSettings)
        
        Task {
            do {
                let result = try await testService.translate(
                    text: "Hello world",
                    from: "en",
                    to: "ru"
                )
                
                await MainActor.run {
                    testResult = "✅ Подключение успешно!\n\nТестовый перевод:\n\(result)"
                    showingTestResult = true
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Ошибка подключения:\n\(error.localizedDescription)"
                    showingTestResult = true
                    isTestingConnection = false
                }
            }
        }
    }
}

// MARK: - TranslationService.swift (Сервис перевода)
import Foundation

class TranslationService: ObservableObject {
    private var settingsManager: SettingsManager?
    
    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
    }
    
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        guard let settings = settingsManager, settings.isConfigured else {
            throw TranslationError.notConfigured
        }
        
        let prompt = createTranslationPrompt(text: text, from: sourceLanguage, to: targetLanguage)
        
        guard let url = URL(string: "\(settings.apiUrl)/chat/completions") else {
            throw TranslationError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens,
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw TranslationError.invalidRequest
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.networkError
            }
            
            if httpResponse.statusCode != 200 {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    throw TranslationError.apiError(detail)
                } else {
                    throw TranslationError.httpError(httpResponse.statusCode)
                }
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.invalidResponse
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            if error is TranslationError {
                throw error
            } else {
                throw TranslationError.networkError
            }
        }
    }
    
    private func createTranslationPrompt(text: String, from sourceLanguage: String, to targetLanguage: String) -> String {
        let languageNames: [String: String] = [
            "auto": "автоматически определить язык",
            "en": "английский",
            "ru": "русский",
            "zh": "китайский",
            "es": "испанский",
            "fr": "французский",
            "de": "немецкий",
            "ja": "японский",
            "ko": "корейский",
            "it": "итальянский",
            "pt": "португальский",
            "ar": "арабский",
            "hi": "хинди",
            "tr": "турецкий"
        ]
        
        let sourceName = languageNames[sourceLanguage] ?? sourceLanguage
        let targetName = languageNames[targetLanguage] ?? targetLanguage
        
        let sourceInstruction = sourceLanguage == "auto"
            ? "Автоматически определи исходный язык текста и"
            : "Переведи с языка \(sourceName)"
        
        return """
        \(sourceInstruction) на \(targetName) следующий текст. 
        Сохрани стиль и тон оригинала. Верни только переведённый текст без дополнительных пояснений.
        
        Текст для перевода:
        \(text)
        """
    }
}

// MARK: - SettingsManager.swift (Управление настройками)
import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    @Published var apiUrl: String = ""
    @Published var apiToken: String = ""
    @Published var modelName: String = ""
    @Published var temperature: Double = 0.3
    @Published var maxTokens: Int = 1024
    
    var isConfigured: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty && !modelName.isEmpty
    }
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        apiUrl = userDefaults.string(forKey: "apiUrl") ?? ""
        apiToken = userDefaults.string(forKey: "apiToken") ?? ""
        modelName = userDefaults.string(forKey: "modelName") ?? ""
        
        let savedTemperature = userDefaults.double(forKey: "temperature")
        temperature = savedTemperature == 0 ? 0.3 : savedTemperature
        
        let savedMaxTokens = userDefaults.integer(forKey: "maxTokens")
        maxTokens = savedMaxTokens == 0 ? 1024 : savedMaxTokens
    }
    
    func saveSettings() {
        userDefaults.set(apiUrl, forKey: "apiUrl")
        userDefaults.set(apiToken, forKey: "apiToken")
        userDefaults.set(modelName, forKey: "modelName")
        userDefaults.set(temperature, forKey: "temperature")
        userDefaults.set(maxTokens, forKey: "maxTokens")
    }
}

// MARK: - TranslationError.swift (Обработка ошибок)
import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidRequest
    case networkError
    case httpError(Int)
    case apiError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Настройки не сконфигурированы. Проверьте URL API, токен и модель."
        case .invalidURL:
            return "Неверный URL API. Проверьте настройки."
        case .invalidRequest:
            return "Ошибка формирования запроса."
        case .networkError:
            return "Ошибка сети. Проверьте интернет соединение."
        case .httpError(let code):
            return "HTTP ошибка: \(code). Проверьте настройки API."
        case .apiError(let message):
            return "Ошибка API: \(message)"
        case .invalidResponse:
            return "Неверный формат ответа от сервера."
        }
    }
}

