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
    private weak var settingsWindow: NSWindow? // ИЗМЕНЕНО: weak ссылка
    private weak var mainWindow: NSWindow? // ИЗМЕНЕНО: добавлена weak ссылка для главного окна
    private var sharedSettingsManager = SettingsManager()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any? // ДОБАВЛЕНО: для глобального мониторинга
    
    deinit {
        // Очищаем мониторы событий
        removeEventMonitors()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotKeys()
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupHotKeys() {
        // Добавляем локальный обработчик событий клавиатуры
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Перехватываем событие
            }
            return event // Пропускаем событие дальше
        }
        
        // ДОБАВЛЕНО: Глобальный монитор для закрытия popover при клике вне его
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
    }
    
    private func removeEventMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Проверяем Cmd+, (настройки)
        if event.modifierFlags.contains(.command) &&
           event.charactersIgnoringModifiers == "," {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
            return true
        }
        
        // Проверяем Cmd+O (открыть переводчик)
        if event.modifierFlags.contains(.command) &&
           event.charactersIgnoringModifiers == "o" {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return true
        }
        
        // ДОБАВЛЕНО: Cmd+Q для выхода
        if event.modifierFlags.contains(.command) &&
           event.charactersIgnoringModifiers == "q" {
            DispatchQueue.main.async { [weak self] in
                self?.quit()
            }
            return true
        }
        
        return false
    }
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem?.button else { return }
        
        // УЛУЧШЕНО: создаем собственную иконку
        if let image = createTranslatorIcon() {
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "AI Переводчик")
        }
        
        button.imagePosition = .imageOnly
        
        // Убираем автоматическое меню и настраиваем кастомное поведение
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        setupPopover()
    }
    
    // ДОБАВЛЕНО: Создание кастомной иконки
    private func createTranslatorIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        
        image.lockFocus()
        defer { image.unlockFocus() }
        
        // Рисуем глобус с буквами
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let globeImage = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            
            let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
            globeImage.draw(in: rect)
            
            // Добавляем маленькие буквы AI
            let font = NSFont.systemFont(ofSize: 6, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.controlTextColor
            ]
            
            let aiText = "AI"
            let textSize = aiText.size(withAttributes: attributes)
            let textRect = NSRect(
                x: size.width - textSize.width - 1,
                y: 1,
                width: textSize.width,
                height: textSize.height
            )
            
            // Фон для текста
            NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
            let bgRect = textRect.insetBy(dx: -1, dy: 0)
            NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2).fill()
            
            aiText.draw(in: textRect, withAttributes: attributes)
        }
        
        image.isTemplate = true
        return image
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // Правый клик - показываем контекстное меню
            closePopover()
            showContextMenu()
        } else {
            // Левый клик - показываем/скрываем popover
            togglePopover()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "🌐 Открыть переводчик", action: #selector(showMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "⚙️ Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        
        // ДОБАВЛЕНО: История переводов
        menu.addItem(NSMenuItem(title: "📋 История переводов", action: #selector(showHistory), keyEquivalent: "h"))
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
        popover?.animates = true // ДОБАВЛЕНО: анимация
        popover?.contentViewController = NSHostingController(
            rootView: CompactContentView(settingsManager: sharedSettingsManager)
        )
    }
    
    @objc private func togglePopover() {
        guard let button = statusBarItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                closePopover()
            } else {
                // УЛУЧШЕНО: закрываем все окна перед показом popover
                mainWindow?.close()
                settingsWindow?.close()
                
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.becomeKey()
            }
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
    }
    
    @objc func showMainWindow() {
        // УЛУЧШЕНО: проверяем существующее окно
        if let existingWindow = mainWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        closePopover() // Закрываем popover при открытии главного окна
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "AI Переводчик"
        newWindow.isReleasedWhenClosed = false // ВАЖНО: предотвращаем автоматическое освобождение
        newWindow.minSize = NSSize(width: 600, height: 500) // ДОБАВЛЕНО: минимальный размер
        newWindow.contentView = NSHostingView(
            rootView: ContentView(settingsManager: sharedSettingsManager)
        )
        newWindow.center()
        newWindow.delegate = self // ДОБАВЛЕНО: делегат для обработки закрытия
        
        mainWindow = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showSettings() {
        // УЛУЧШЕНО: проверяем существующее окно
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        closePopover() // Закрываем popover при открытии настроек
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Настройки"
        newWindow.isReleasedWhenClosed = false // ВАЖНО: предотвращаем автоматическое освобождение
        
        // ИЗМЕНЕНО: создаем SettingsView с замыканием для закрытия
        let settingsView = SettingsView(settingsManager: sharedSettingsManager) { [weak newWindow] in
            newWindow?.close()
        }
        
        newWindow.contentView = NSHostingView(rootView: settingsView)
        newWindow.delegate = self
        
        settingsWindow = newWindow
        
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // ДОБАВЛЕНО: метод показа истории
    @objc private func showHistory() {
        let alert = NSAlert()
        alert.messageText = "История переводов"
        alert.informativeText = "Функция истории переводов будет добавлена в следующей версии"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        
        Горячие клавиши:
        • Cmd+O - открыть переводчик
        • Cmd+, - настройки
        • Cmd+Q - выход
        
        Создано для удобного перевода текстов с помощью ИИ.
        """
        aboutPanel.alertStyle = .informational
        aboutPanel.addButton(withTitle: "OK")
        aboutPanel.runModal()
    }
    
    @objc private func quit() {
        // Закрываем все окна
        popover?.performClose(nil)
        settingsWindow?.close()
        mainWindow?.close()
        
        // Очищаем мониторы событий
        removeEventMonitors()
        
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Дополнительная очистка при завершении
        removeEventMonitors()
        
        // Очищаем ссылки на окна
        settingsWindow = nil
        mainWindow = nil
        popover = nil
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // НЕ завершаем приложение при закрытии окон, так как работаем из меню-бара
        return false
    }
}

// MARK: - Расширение для обработки закрытия окон
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == mainWindow {
                mainWindow = nil
                // Возвращаемся в режим accessory при закрытии главного окна
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
}

// MARK: - ContentView.swift (Главный интерфейс)
import SwiftUI

struct ContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var showingSettings = false
    @State private var selectedSourceLanguage = "auto"
    @State private var selectedTargetLanguage = "ru"
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var copyFeedback = false // ДОБАВЛЕНО: обратная связь при копировании
    @State private var keyEventMonitor: Any? // ДОБАВЛЕНО: для отслеживания Cmd+Enter
    
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
        ("tr", "🇹🇷 Türkçe"),
        ("uk", "🇺🇦 Українська"), // ДОБАВЛЕНО: украинский
        ("pl", "🇵🇱 Polski") // ДОБАВЛЕНО: польский
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
                
                // ДОБАВЛЕНО: индикатор статуса подключения
                HStack(spacing: 4) {
                    Circle()
                        .fill(settingsManager.isConfigured ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(settingsManager.isConfigured ? "Подключено" : "Не настроено")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                .help("Поменять языки местами")
                
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
                    
                    // ДОБАВЛЕНО: кнопка очистки
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
                    .onChange(of: inputText) { newValue in
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
                
                // ДОБАВЛЕНО: подсказка о горячей клавише
                Text("⌘↩")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Нажмите Cmd+Enter для быстрого перевода")
                
                // ДОБАВЛЕНО: кнопка вставки из буфера
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
                            
                            // ДОБАВЛЕНО: кнопка очистки результата
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
                .frame(minHeight: 120, maxHeight: 300)
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
        }
        .onDisappear {
            removeKeyboardShortcuts()
        }
    }
    
    // ДОБАВЛЕНО: настройка горячих клавиш
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Проверяем Cmd+Enter для отправки перевода
            if event.modifierFlags.contains(.command) &&
               event.keyCode == 36 && // 36 = Return/Enter
               !self.inputText.isEmpty &&
               !self.isTranslating &&
               self.settingsManager.isConfigured {
                self.translateText()
                return nil // Перехватываем событие
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
    
    private func swapLanguages() {
        guard selectedSourceLanguage != "auto" else { return }
        let temp = selectedSourceLanguage
        selectedSourceLanguage = selectedTargetLanguage
        selectedTargetLanguage = temp
        
        // Также меняем местами тексты
        let tempText = inputText
        inputText = outputText
        outputText = tempText
    }
    
    private func translateText() {
        guard !inputText.isEmpty, settingsManager.isConfigured else { return }
        
        isTranslating = true
        outputText = ""
        errorMessage = ""
        
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
        
        // Показываем обратную связь
        withAnimation(.easeInOut(duration: 0.2)) {
            copyFeedback = true
        }
        
        // Убираем обратную связь через 2 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copyFeedback = false
            }
        }
    }
    
    // ДОБАВЛЕНО: вставка из буфера
    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            inputText = string
        }
    }
}

// MARK: - CompactContentView (Компактный вид для popover)
struct CompactContentView: View {
    @StateObject private var translationService = TranslationService()
    @ObservedObject var settingsManager: SettingsManager
    
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var selectedSourceLanguage = "auto"
    @State private var selectedTargetLanguage = "ru"
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var copyFeedback = false // ДОБАВЛЕНО
    @State private var keyEventMonitor: Any? // ДОБАВЛЕНО: для отслеживания Cmd+Enter
    
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
        ("tr", "🇹🇷 TR"),
        ("uk", "🇺🇦 UA"), // ДОБАВЛЕНО
        ("pl", "🇵🇱 PL") // ДОБАВЛЕНО
    ]
    
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Заголовок с индикатором статуса
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                Text("AI Переводчик")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Индикатор статуса
                Circle()
                    .fill(settingsManager.isConfigured ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                
                // Кнопка полной версии
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
                        .font(.caption)
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
                
                // Кнопка вставки
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Вставить из буфера")
            }
            .padding(.horizontal)
            
            // Поле ввода (компактное)
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
            
            // Результат (компактный)
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
            
            // Предупреждение о настройках
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
        }
        .onDisappear {
            removeKeyboardShortcuts()
        }
        .alert("Ошибка", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // ДОБАВЛЕНО: настройка горячих клавиш
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Проверяем Cmd+Enter для отправки перевода
            if event.modifierFlags.contains(.command) &&
               event.keyCode == 36 && // 36 = Return/Enter
               !self.inputText.isEmpty &&
               !self.isTranslating &&
               self.settingsManager.isConfigured {
                self.translateText()
                return nil // Перехватываем событие
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
        
        // Обратная связь
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

// MARK: - SettingsView.swift (Настройки)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    let onClose: (() -> Void)? // ДОБАВЛЕНО: замыкание для закрытия
    
    @State private var apiUrl = ""
    @State private var apiToken = ""
    @State private var modelName = ""
    @State private var temperature = 0.3
    @State private var maxTokens = 1024
    @State private var isTestingConnection = false
    @State private var testResult = ""
    @State private var showingTestResult = false
    @State private var showAdvancedSettings = false // ДОБАВЛЕНО: расширенные настройки
    
    init(settingsManager: SettingsManager, onClose: (() -> Void)? = nil) {
        self.settingsManager = settingsManager
        self.onClose = onClose
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Основные настройки
                    GroupBox(label: Label("🔗 Подключение к OpenWebUI", systemImage: "network")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("URL API:")
                                    .font(.headline)
                                TextField("https://your-openwebui.com/v1", text: $apiUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .help("Базовый URL вашего OpenWebUI API")
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Token:")
                                    .font(.headline)
                                HStack {
                                    SecureField("Ваш API токен", text: $apiToken)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    // ДОБАВЛЕНО: кнопка показа/скрытия токена
                                    Button(action: {}) {
                                        Image(systemName: "eye.slash")
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(true) // TODO: реализовать переключение видимости
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Модель для перевода:")
                                    .font(.headline)
                                TextField("gpt-4, claude-3-sonnet, llama2 и т.д.", text: $modelName)
                                    .textFieldStyle(.roundedBorder)
                                    .help("Название модели в вашем OpenWebUI")
                            }
                        }
                        .padding()
                    }
                    
                    // Параметры генерации
                    GroupBox(label: Label("⚙️ Параметры генерации", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Temperature:")
                                        .font(.headline)
                                    Spacer()
                                    Text(String(format: "%.1f", temperature))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                                Text("Контролирует креативность перевода (0.0 - точный, 1.0 - творческий)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Max Tokens:")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(maxTokens)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                Slider(value: Binding(
                                    get: { Double(maxTokens) },
                                    set: { maxTokens = Int($0) }
                                ), in: 256...4096, step: 256)
                                Text("Максимальная длина ответа")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // ДОБАВЛЕНО: кнопка сброса к значениям по умолчанию
                            Button("Сбросить к значениям по умолчанию") {
                                temperature = 0.3
                                maxTokens = 1024
                            }
                            .font(.caption)
                            .buttonStyle(LinkButtonStyle())
                        }
                        .padding()
                    }
                    
                    // Тестирование
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
                                    Text(isTestingConnection ? "Тестируем подключение..." : "Тест подключения")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty || isTestingConnection)
                            
                            if !testResult.isEmpty {
                                Text(testResult)
                                    .font(.caption)
                                    .foregroundColor(testResult.contains("✅") ? .green : .red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()
                    }
                    
                    // Информация
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
                .padding()
            }
            .frame(width: 600, height: 700)
            .navigationTitle("Настройки AI Переводчика")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        loadSettings()
                        onClose?() ?? dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveSettings()
                        onClose?() ?? dismiss()
                    }
                    .disabled(apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private let instructionSteps = [
        "Откройте ваш OpenWebUI",
        "Перейдите в Settings → Account → API Keys",
        "Нажмите 'Create new API key'",
        "Скопируйте созданный ключ",
        "URL обычно имеет вид: https://your-domain.com/v1"
    ]
    
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
        testResult = ""
        
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
}

// MARK: - TranslationService.swift (Сервис перевода)
import Foundation

class TranslationService: ObservableObject {
    private var settingsManager: SettingsManager?
    private let session: URLSession
    
    init() {
        // УЛУЧШЕНО: настраиваем URLSession с таймаутом
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }
    
    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
    }
    
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        guard let settings = settingsManager, settings.isConfigured else {
            throw TranslationError.notConfigured
        }
        
        let prompt = createTranslationPrompt(text: text, from: sourceLanguage, to: targetLanguage)
        
        // УЛУЧШЕНО: более гибкая обработка URL
        var urlString = settings.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        if !urlString.hasSuffix("chat/completions") && !urlString.hasSuffix("v1/") {
            urlString += "chat/completions"
        } else if urlString.hasSuffix("v1/") {
            urlString += "chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a professional translator. Translate accurately while preserving the tone and style of the original text."
                ],
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
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.networkError
            }
            
            // УЛУЧШЕНО: более подробная обработка ошибок
            if httpResponse.statusCode != 200 {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let detail = errorData["detail"] as? String {
                        throw TranslationError.apiError(detail)
                    } else if let error = errorData["error"] as? [String: Any],
                              let message = error["message"] as? String {
                        throw TranslationError.apiError(message)
                    }
                }
                throw TranslationError.httpError(httpResponse.statusCode)
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
            "tr": "турецкий",
            "uk": "украинский",
            "pl": "польский"
        ]
        
        let sourceName = languageNames[sourceLanguage] ?? sourceLanguage
        let targetName = languageNames[targetLanguage] ?? targetLanguage
        
        let sourceInstruction = sourceLanguage == "auto"
            ? "Автоматически определи исходный язык текста и"
            : "Переведи с языка \(sourceName)"
        
        return """
        \(sourceInstruction) на \(targetName) следующий текст. 
        Сохрани стиль, тон и форматирование оригинала. 
        Верни только переведённый текст без дополнительных пояснений или комментариев.
        
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
    
    // ДОБАВЛЕНО: метод для сброса настроек
    func resetToDefaults() {
        apiUrl = ""
        apiToken = ""
        modelName = ""
        temperature = 0.3
        maxTokens = 1024
        saveSettings()
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
            return "HTTP ошибка: \(code). \(httpErrorDescription(code))"
        case .apiError(let message):
            return "Ошибка API: \(message)"
        case .invalidResponse:
            return "Неверный формат ответа от сервера."
        }
    }
    
    private func httpErrorDescription(_ code: Int) -> String {
        switch code {
        case 401:
            return "Неверный API токен."
        case 403:
            return "Доступ запрещен. Проверьте права доступа."
        case 404:
            return "API endpoint не найден. Проверьте URL."
        case 429:
            return "Слишком много запросов. Попробуйте позже."
        case 500...599:
            return "Ошибка сервера. Попробуйте позже."
        default:
            return "Проверьте настройки API."
        }
    }
}

// MARK: - Custom Button Styles
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .blue.opacity(0.7) : .blue)
            .underline()
    }
}
