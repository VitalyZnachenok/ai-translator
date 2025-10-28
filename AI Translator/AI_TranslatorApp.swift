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
    private weak var settingsWindow: NSWindow?
    private weak var mainWindow: NSWindow?
    private var sharedSettingsManager = SettingsManager()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    deinit {
        removeEventMonitors()
        stopGlobalHotkey()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotKeys()
        requestAccessibilityPermissions()
        setupGlobalHotkey()
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Требуется разрешение"
            alert.informativeText = """
            Для использования глобальных горячих клавиш приложению требуется доступ к универсальному доступу.
            
            Пожалуйста, добавьте AI Переводчик в:
            Системные настройки → Защита и безопасность → Конфиденциальность → Универсальный доступ
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
    
    private func setupGlobalHotkey() {
        stopGlobalHotkey()
        
        guard AXIsProcessTrusted() else {
            print("Нет доступа к Accessibility")
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                
                if appDelegate.checkHotkey(event: event) {
                    // Перехватываем событие
                    DispatchQueue.main.async {
                        appDelegate.quickTranslateFromClipboard()
                    }
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Не удалось создать event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func stopGlobalHotkey() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
    
    private func checkHotkey(event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Получаем сохраненную горячую клавишу
        let hotkeyString = sharedSettingsManager.quickTranslateHotkey
        let (savedKeyCode, savedModifiers) = parseHotkeyString(hotkeyString)
        
        // Проверяем модификаторы
        var currentModifiers: CGEventFlags = []
        if flags.contains(.maskCommand) { currentModifiers.insert(.maskCommand) }
        if flags.contains(.maskShift) { currentModifiers.insert(.maskShift) }
        if flags.contains(.maskAlternate) { currentModifiers.insert(.maskAlternate) }
        if flags.contains(.maskControl) { currentModifiers.insert(.maskControl) }
        
        // Сравниваем с сохраненной комбинацией
        return keyCode == savedKeyCode && currentModifiers == savedModifiers
    }
    
    private func parseHotkeyString(_ hotkey: String) -> (Int64, CGEventFlags) {
        var modifiers: CGEventFlags = []
        var keyCode: Int64 = 0x11 // T по умолчанию
        
        // Парсим модификаторы
        if hotkey.contains("⌘") { modifiers.insert(.maskCommand) }
        if hotkey.contains("⇧") { modifiers.insert(.maskShift) }
        if hotkey.contains("⌥") { modifiers.insert(.maskAlternate) }
        if hotkey.contains("⌃") { modifiers.insert(.maskControl) }
        
        // Получаем последний символ и конвертируем в keyCode
        if let lastChar = hotkey.last {
            keyCode = Int64(keyCodeForCharacter(lastChar))
        }
        
        return (keyCode, modifiers)
    }
    
    private func keyCodeForCharacter(_ char: Character) -> UInt16 {
        switch char.uppercased() {
        case "A": return 0x00
        case "S": return 0x01
        case "D": return 0x02
        case "F": return 0x03
        case "H": return 0x04
        case "G": return 0x05
        case "Z": return 0x06
        case "X": return 0x07
        case "C": return 0x08
        case "V": return 0x09
        case "B": return 0x0B
        case "Q": return 0x0C
        case "W": return 0x0D
        case "E": return 0x0E
        case "R": return 0x0F
        case "Y": return 0x10
        case "T": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "O": return 0x1F
        case "U": return 0x20
        case "[": return 0x21
        case "I": return 0x22
        case "P": return 0x23
        case "L": return 0x25
        case "J": return 0x26
        case "K": return 0x28
        case "N": return 0x2D
        case "M": return 0x2E
        default: return 0x11 // T по умолчанию
        }
    }
    
    private func setupHotKeys() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
        
        // Подписываемся на изменение горячей клавиши
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: Notification.Name("HotkeyChanged"),
            object: nil
        )
    }
    
    @objc private func hotkeyChanged() {
        setupGlobalHotkey() // Перерегистрируем с новой комбинацией
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
        if event.modifierFlags.contains(.command) &&
           event.charactersIgnoringModifiers == "," {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
            return true
        }
        
        if event.modifierFlags.contains(.command) &&
           event.charactersIgnoringModifiers == "o" {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return true
        }
        
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
        
        if let image = createTranslatorIcon() {
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "AI Переводчик")
        }
        
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        setupPopover()
    }
    
    private func createTranslatorIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        
        image.lockFocus()
        defer { image.unlockFocus() }
        
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let globeImage = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            
            let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
            globeImage.draw(in: rect)
            
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
            closePopover()
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "🌐 Открыть переводчик", action: #selector(showMainWindow), keyEquivalent: "o"))
        
        menu.addItem(NSMenuItem.separator())
        
        // Получаем текущую горячую клавишу из настроек
        let hotkeyDisplay = sharedSettingsManager.quickTranslateHotkey
        let quickTranslateItem = NSMenuItem(title: "⚡ Перевести выделенный текст (\(hotkeyDisplay))", action: #selector(quickTranslateFromClipboard), keyEquivalent: "")
        menu.addItem(quickTranslateItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "⚙️ Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "📋 История переводов", action: #selector(showHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "📖 О программе", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "❌ Выйти", action: #selector(quit), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        guard let button = statusBarItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    @objc private func quickTranslateFromClipboard() {
        // Сохраняем текущее содержимое буфера
        let oldClipboard = NSPasteboard.general.string(forType: .string)
        
        // Очищаем буфер обмена
        NSPasteboard.general.clearContents()
        
        // Симулируем Cmd+C для копирования выделенного текста
        simulateCopy()
        
        // Даем время на копирование
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            
            // Получаем скопированный текст
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                // Восстанавливаем старый буфер если ничего не скопировалось
                if let oldText = oldClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(oldText, forType: .string)
                }
                
                let alert = NSAlert()
                alert.messageText = "Нет выделенного текста"
                alert.informativeText = "Выделите текст для перевода и попробуйте снова"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            
            // Открываем главное окно
            self.showMainWindow()
            
            // Отправляем текст для перевода
            UserDefaults.standard.set(text, forKey: "pendingTranslationText")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("QuickTranslateText"), object: nil)
                
                // Восстанавливаем старый буфер обмена после небольшой задержки
                if let oldText = oldClipboard, oldText != text {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(oldText, forType: .string)
                    }
                }
            }
        }
    }
    
    private func simulateCopy() {
        // Создаем событие нажатия Cmd+C
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Создаем событие для клавиши C с модификатором Cmd
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) {
            keyUpEvent.flags = .maskCommand
            keyUpEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 450, height: 550)
        popover?.behavior = .transient
        popover?.animates = true
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
        if let existingWindow = mainWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        closePopover()
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "AI Переводчик"
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 700, height: 600)
        newWindow.maxSize = NSSize(width: 1200, height: 1000)
        
        let contentView = ContentView(settingsManager: sharedSettingsManager)
            .background(Color(NSColor.windowBackgroundColor))
        
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.delegate = self
        
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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Настройки AI Переводчика"
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 680, height: 750)
        newWindow.maxSize = NSSize(width: 900, height: 1000)
        
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
        • Перевод между 16 языками
        • Интеграция с любыми AI моделями
        • Работа из меню-бара
        • Быстрый доступ и компактный интерфейс
        • Кастомные промпты для разных стилей перевода
        • Быстрый перевод выделенного текста
        • Автоматическое копирование и восстановление буфера
        
        Горячие клавиши:
        • Cmd+O - открыть переводчик
        • Настраиваемая горячая клавиша - перевести выделенный текст
        • Cmd+, - настройки
        • Cmd+Q - выход
        
        Создано для удобного перевода текстов с помощью ИИ.
        """
        aboutPanel.alertStyle = .informational
        aboutPanel.addButton(withTitle: "OK")
        aboutPanel.runModal()
    }
    
    @objc private func quit() {
        popover?.performClose(nil)
        settingsWindow?.close()
        mainWindow?.close()
        
        removeEventMonitors()
        
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitors()
        
        settingsWindow = nil
        mainWindow = nil
        popover = nil
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == mainWindow {
                mainWindow = nil
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
    @State private var selectedPromptId = "default"
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var copyFeedback = false
    @State private var keyEventMonitor: Any?
    @State private var notificationObserver: Any?
    
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
        ("uk", "🇺🇦 Українська"),
        ("pl", "🇵🇱 Polski")
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
        ) { _ in
            if let text = UserDefaults.standard.string(forKey: "pendingTranslationText") {
                self.inputText = text
                UserDefaults.standard.removeObject(forKey: "pendingTranslationText")
                
                if self.settingsManager.isConfigured {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.translateText()
                    }
                }
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

// MARK: - CompactContentView (Компактный вид для popover)
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
        ("uk", "🇺🇦 UA"),
        ("pl", "🇵🇱 PL")
    ]
    
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
                
                // Селектор профилей (компактный)
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
                    ForEach(languages, id: \.0) { code, name in
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
                    ForEach(languages.filter { $0.0 != "auto" }, id: \.0) { code, name in
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
                            .help("Стандартный стиль")
                        ForEach(settingsManager.customPrompts) { prompt in
                            Text(prompt.icon).tag(prompt.id)
                                .help(prompt.name)
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
        ) { _ in
            if let text = UserDefaults.standard.string(forKey: "pendingTranslationText") {
                self.inputText = text
                UserDefaults.standard.removeObject(forKey: "pendingTranslationText")
                
                if self.settingsManager.isConfigured {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.translateText()
                    }
                }
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

// MARK: - SettingsView.swift (Настройки)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    let onClose: (() -> Void)?
    
    @State private var apiUrl = ""
    @State private var apiToken = ""
    @State private var selectedModelId = ""
    @State private var temperature = 0.3
    @State private var maxTokens = 1024
    @State private var isTestingConnection = false
    @State private var testResult = ""
    @State private var showingTestResult = false
    @State private var showAdvancedSettings = false
    @State private var selectedTab = 0
    
    @State private var customPrompts: [TranslationPrompt] = []
    @State private var showingAddPrompt = false
    @State private var editingPrompt: TranslationPrompt?
    
    // ДОБАВЛЕНО: для работы с моделями
    @StateObject private var modelService = ModelService()
    @State private var availableModels: [OpenWebUIModel] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String = ""
    @State private var canLoadModels = false
    
    // ДОБАВЛЕНО: для настройки горячих клавиш
    @State private var quickTranslateHotkey = "⌘⇧T"
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    
    // ДОБАВЛЕНО: для управления профилями
    @State private var showingAddProfile = false
    @State private var editingProfile: ConnectionProfile?
    @State private var selectedProfileName = ""
    @State private var selectedProfileIcon = "🌐"
    
    init(settingsManager: SettingsManager, onClose: (() -> Void)? = nil) {
        self.settingsManager = settingsManager
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок и кнопки управления
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
                
                VStack {
                    promptsSettings
                }
                .tabItem {
                    Label("Стили перевода", systemImage: "text.bubble")
                }
                .tag(1)
                
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
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200))
                    ], spacing: 12) {
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
    
    // ДОБАВЛЕНО: Интерфейс настройки горячих клавиш
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
                    
                    Divider()
                    
                    Text("Альтернативный способ:")
                        .font(.headline)
                    
                    Text("Правый клик на иконке в меню-баре → \"Перевести выделенный текст\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            Spacer()
        }
    }
    
    private func startRecordingHotkey() {
        isRecordingHotkey = true
        
        // Удаляем старый монитор если есть
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Создаем новый монитор для записи горячей клавиши
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
            
            // Требуем хотя бы один модификатор
            if !modifiers.isEmpty {
                let keyChar = self.keyCharacterForKeyCode(event.keyCode)
                self.quickTranslateHotkey = modifiers.joined() + keyChar
                self.settingsManager.quickTranslateHotkey = self.quickTranslateHotkey
                self.stopRecordingHotkey()
                return nil // Перехватываем событие
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
    
    private func keyCharacterForKeyCode(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"
        case 0x24: return "↩"
        case 0x30: return "⇥"
        case 0x31: return "Space"
        case 0x33: return "⌫"
        case 0x35: return "⎋"
        default: return "?"
        }
    }
    
    private let instructionSteps = [
        "Откройте ваш OpenWebUI",
        "Перейдите в Settings → Account → API Keys",
        "Нажмите 'Create new API key'",
        "Скопируйте созданный ключ",
        "URL обычно имеет вид: https://your-domain.com/v1",
        "Нажмите 'Обновить' для загрузки списка доступных моделей"
    ]
    
    private func updateCanLoadModels() {
        canLoadModels = !apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                       !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if canLoadModels {
            modelsError = ""
        }
    }
    
    private func loadModels() {
        guard canLoadModels else { return }
        
        isLoadingModels = true
        modelsError = ""
        
        Task {
            do {
                let models = try await modelService.fetchAvailableModels(
                    apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    self.availableModels = models
                    self.isLoadingModels = false
                    
                    // Если текущая модель не найдена в списке, сбрасываем выбор
                    if !selectedModelId.isEmpty && !models.contains(where: { $0.id == selectedModelId }) {
                        selectedModelId = ""
                    }
                }
            } catch {
                await MainActor.run {
                    self.modelsError = "Ошибка загрузки моделей: \(error.localizedDescription)"
                    self.isLoadingModels = false
                    self.availableModels = []
                }
            }
        }
    }
    
    private func loadSettings() {
        loadSettingsFromActiveProfile()
        customPrompts = settingsManager.customPrompts
        quickTranslateHotkey = settingsManager.quickTranslateHotkey
        updateCanLoadModels()
        
        // Автоматически загружаем модели если настройки заполнены
        if canLoadModels {
            loadModels()
        }
    }
    
    private func loadSettingsFromActiveProfile() {
        if let profile = settingsManager.activeProfile {
            apiUrl = profile.apiUrl
            apiToken = profile.apiToken
            selectedModelId = profile.modelName
            temperature = profile.temperature
            maxTokens = profile.maxTokens
        } else {
            apiUrl = ""
            apiToken = ""
            selectedModelId = ""
            temperature = 0.3
            maxTokens = 1024
        }
        updateCanLoadModels()
    }
    
    private func saveSettings() {
        // Обновляем активный профиль
        if var profile = settingsManager.activeProfile {
            profile.apiUrl = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.modelName = selectedModelId
            profile.temperature = temperature
            profile.maxTokens = maxTokens
            settingsManager.updateProfile(profile)
        }
        
        settingsManager.customPrompts = customPrompts
        
        // Проверяем, изменилась ли горячая клавиша
        let hotkeyChanged = settingsManager.quickTranslateHotkey != quickTranslateHotkey
        settingsManager.quickTranslateHotkey = quickTranslateHotkey
        
        settingsManager.saveSettings()
        
        // Отправляем уведомление об изменении горячей клавиши
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
        
        let tempSettings = SettingsManager()
        tempSettings.apiUrl = apiUrl
        tempSettings.apiToken = apiToken
        tempSettings.modelName = selectedModelId
        tempSettings.temperature = temperature
        tempSettings.maxTokens = maxTokens
        
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
}

// MARK: - PromptEditView (Редактор промптов)
struct PromptEditView: View {
    let prompt: TranslationPrompt?
    let onSave: (TranslationPrompt) -> Void
    
    @State private var name = ""
    @State private var description = ""
    @State private var icon = "✨"
    @State private var systemPrompt = ""
    @State private var userPromptAddition = ""
    @Environment(\.dismiss) private var dismiss
    
    private let availableIcons = ["✨", "💬", "📚", "⚙️", "💼", "🎯", "🔥", "💡", "🎨", "🚀", "📝", "🌟"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text(prompt == nil ? "Новый стиль перевода" : "Редактировать стиль")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                Section("Основная информация") {
                    HStack {
                        Text("Иконка:")
                        Picker("", selection: $icon) {
                            ForEach(availableIcons, id: \.self) { emoji in
                                Text(emoji).tag(emoji)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    TextField("Название стиля", text: $name)
                    TextField("Краткое описание", text: $description)
                }
                
                Section("Настройки промпта") {
                    VStack(alignment: .leading) {
                        Text("Системный промпт:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12))
                            .frame(height: 80)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Дополнение к запросу пользователя:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $userPromptAddition)
                            .font(.system(size: 12))
                            .frame(height: 60)
                    }
                }
            }
            
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Сохранить") {
                    let newPrompt = TranslationPrompt(
                        id: prompt?.id ?? UUID().uuidString,
                        name: name,
                        description: description,
                        icon: icon,
                        systemPrompt: systemPrompt,
                        userPromptAddition: userPromptAddition
                    )
                    onSave(newPrompt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || systemPrompt.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            if let prompt = prompt {
                name = prompt.name
                description = prompt.description
                icon = prompt.icon
                systemPrompt = prompt.systemPrompt
                userPromptAddition = prompt.userPromptAddition
            }
        }
    }
}

// MARK: - ProfileCard (Карточка профиля)
struct ProfileCard: View {
    let profile: ConnectionProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.icon)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(profile.modelName.isEmpty ? "Модель не выбрана" : profile.modelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            
            HStack {
                Circle()
                    .fill(profile.isConfigured ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(profile.isConfigured ? "Настроен" : "Не настроен")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Button("Редактировать") {
                        onEdit()
                    }
                    
                    Button("Дублировать") {
                        onDuplicate()
                    }
                    
                    Divider()
                    
                    Button("Удалить", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - ProfileEditView (Редактор профилей)
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
    @State private var showingTestResult = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let availableIcons = ["🌐", "🔗", "🛜", "⚡", "🚀", "💻", "🖥️", "📡", "🌟", "💎", "🔥", "⚙️"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text(profile == nil ? "Новый профиль подключения" : "Редактировать профиль")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                Section("Основная информация") {
                    HStack {
                        Text("Иконка:")
                        Picker("", selection: $icon) {
                            ForEach(availableIcons, id: \.self) { emoji in
                                Text(emoji).tag(emoji)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    TextField("Название профиля", text: $name)
                        .help("Например: 'Основной сервер' или 'Локальный Ollama'")
                }
                
                Section("Настройки подключения") {
                    TextField("URL API", text: $apiUrl)
                        .help("Например: https://your-openwebui.com/v1")
                    
                    SecureField("API Token", text: $apiToken)
                    
                    TextField("Модель", text: $modelName)
                        .help("Например: gpt-4o-mini или llama3.2:latest")
                }
                
                Section("Параметры генерации") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature:")
                            Spacer()
                            Text(String(format: "%.1f", temperature))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens:")
                            Spacer()
                            Text("\(maxTokens)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { Double(maxTokens) },
                            set: { maxTokens = Int($0) }
                        ), in: 256...4096, step: 256)
                    }
                }
                
                Section("Тестирование") {
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
                    .disabled(apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty || isTestingConnection)
                    
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundColor(testResult.contains("✅") ? .green : .red)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Сохранить") {
                    let newProfile = ConnectionProfile(
                        id: profile?.id ?? UUID().uuidString,
                        name: name,
                        apiUrl: apiUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines),
                        modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                        temperature: temperature,
                        maxTokens: maxTokens,
                        icon: icon
                    )
                    onSave(newProfile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || apiUrl.isEmpty || apiToken.isEmpty || modelName.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(width: 600, height: 700)
        .onAppear {
            if let profile = profile {
                name = profile.name
                apiUrl = profile.apiUrl
                apiToken = profile.apiToken
                modelName = profile.modelName
                temperature = profile.temperature
                maxTokens = profile.maxTokens
                icon = profile.icon
            } else {
                // Значения по умолчанию для нового профиля
                name = "Новый профиль"
                temperature = 0.3
                maxTokens = 1024
                icon = "🌐"
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = ""
        
        let tempSettings = SettingsManager()
        let tempProfile = ConnectionProfile(
            name: "Test",
            apiUrl: apiUrl,
            apiToken: apiToken,
            modelName: modelName,
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
}

// MARK: - ModelService.swift (Сервис для работы с моделями)
import Foundation

struct OpenWebUIModel: Codable, Identifiable {
    let id: String
    let name: String?
    let object: String?
    let owned_by: String?
    let created: Int?
    
    // Дополнительные поля для Ollama
    let ollama: OllamaInfo?
    let connection_type: String?
    let tags: [String]?
    let actions: [String]?
    let filters: [String]?
    let arena: Bool?
    let info: ModelInfo?
    
    // Альтернативные поля, которые могут присутствовать
    let model: String?
    
    var displayName: String {
        // Сначала пробуем name, потом id
        let modelName = name ?? model ?? id
        
        // Показываем более читаемое имя, убирая префиксы провайдеров
        let cleanName = modelName
            .replacingOccurrences(of: "ollama:", with: "")
            .replacingOccurrences(of: "openai:", with: "")
            .replacingOccurrences(of: "anthropic:", with: "")
            .replacingOccurrences(of: "google:", with: "")
        return cleanName.isEmpty ? id : cleanName
    }
    
    var providerIcon: String {
        let modelName = name ?? model ?? id
        
        if modelName.contains("gpt") || modelName.contains("openai") {
            return "🤖"
        } else if modelName.contains("claude") || modelName.contains("anthropic") {
            return "🧠"
        } else if modelName.contains("gemini") || modelName.contains("google") || modelName.contains("gemma") {
            return "💎"
        } else if modelName.contains("llama") {
            return "🦙"
        } else if modelName.contains("mistral") {
            return "🌪️"
        } else if modelName.contains("phi") {
            return "🔬"
        } else if modelName.contains("qwen") {
            return "🐧"
        } else if modelName.contains("arena") {
            return "🏟️"
        } else if owned_by == "ollama" || connection_type == "local" {
            return "🦙"  // Ollama models
        } else {
            return "⚡"
        }
    }
}

// Дополнительные структуры для поддержки полного формата Ollama
struct OllamaInfo: Codable {
    let name: String?
    let model: String?
    let modified_at: String?
    let size: Int?
    let digest: String?
    let details: ModelDetails?
    let connection_type: String?
    let urls: [Int]?
    let expires_at: Int?
}

struct ModelDetails: Codable {
    let parent_model: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

struct ModelInfo: Codable {
    let meta: ModelMeta?
}

struct ModelMeta: Codable {
    let profile_image_url: String?
    let description: String?
    let model_ids: [String]?
}

struct ModelsResponse: Codable {
    let data: [OpenWebUIModel]
    let object: String?  // Делаем опциональным
}

// Альтернативный формат ответа (если сервер возвращает массив напрямую)
struct DirectModelsResponse: Codable {
    let models: [OpenWebUIModel]
}

// Еще один возможный формат (просто массив моделей)
typealias ModelsArrayResponse = [OpenWebUIModel]

class ModelService: ObservableObject {
    private var session: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }
    
    func fetchAvailableModels(apiUrl: String, apiToken: String) async throws -> [OpenWebUIModel] {
        var urlString = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Убираем завершающий слеш если есть
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        
        // Формируем правильный URL для моделей
        if urlString.hasSuffix("/api") {
            urlString += "/v1/models"
        } else if urlString.hasSuffix("/api/v1") {
            urlString += "/models"
        } else if urlString.contains("/api/v1/chat/completions") {
            urlString = urlString.replacingOccurrences(of: "/chat/completions", with: "/models")
        } else if !urlString.contains("/models") {
            // Если URL не содержит нужный путь, добавляем стандартный
            if urlString.contains("/api") && !urlString.contains("/v1") {
                urlString += "/v1/models"
            } else if urlString.contains("/v1") {
                urlString += "/models"
            } else {
                urlString += "/api/v1/models"
            }
        }
        
        print("Запрос моделей по URL: \(urlString)") // Для отладки
        
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AI-Translator/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)") // Для отладки
        print("Response headers: \(httpResponse.allHeaderFields)") // Для отладки
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("Error response: \(responseString)") // Для отладки
            
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
        
        // Добавляем отладку ответа
        let responseString = String(data: data, encoding: .utf8) ?? "No response body"
        print("Response data: \(responseString)") // Для отладки
        
        do {
            // Пробуем стандартный формат OpenAI API
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            print("✅ Successfully parsed \(modelsResponse.data.count) models using standard format")
            let models = modelsResponse.data.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            for model in models {
                print("Model: \(model.id) -> \(model.displayName) (\(model.providerIcon))")
            }
            return models
        } catch {
            print("❌ Standard format failed: \(error)")
            print("Trying alternative formats...")
            
            // Пробуем формат с полем "models"
            do {
                let directResponse = try JSONDecoder().decode(DirectModelsResponse.self, from: data)
                print("✅ Successfully parsed \(directResponse.models.count) models using direct format")
                return directResponse.models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            } catch {
                print("❌ Direct format failed: \(error)")
                print("Trying array format...")
                
                // Пробуем простой массив моделей
                do {
                    let arrayResponse = try JSONDecoder().decode(ModelsArrayResponse.self, from: data)
                    print("✅ Successfully parsed \(arrayResponse.count) models using array format")
                    return arrayResponse.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                } catch {
                    print("❌ All JSON decode attempts failed")
                    print("Final decode error: \(error)")
                    throw TranslationError.invalidResponse
                }
            }
        }
    }
}

// MARK: - TranslationService.swift (Сервис перевода)
import Foundation

class TranslationService: ObservableObject {
    private var settingsManager: SettingsManager?
    private var session: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }
    
    func configure(with settings: SettingsManager) {
        self.settingsManager = settings
    }
    
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String, customPrompt: TranslationPrompt? = nil) async throws -> String {
        guard let settings = settingsManager, settings.isConfigured else {
            throw TranslationError.notConfigured
        }
        
        let prompt = createTranslationPrompt(text: text, from: sourceLanguage, to: targetLanguage, customPrompt: customPrompt)
        
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
        
        let systemMessage = customPrompt?.systemPrompt ?? "You are a professional translator. Translate accurately while preserving the tone and style of the original text."
        
        let requestBody: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                [
                    "role": "system",
                    "content": systemMessage
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
        request.setValue("AI-Translator/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw TranslationError.invalidRequest
        }
        
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TranslationError.networkError
                }
                
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
                lastError = error
                
                if !(error is URLError) || attempt == 3 {
                    if error is TranslationError {
                        throw error
                    } else if let urlError = error as? URLError {
                        switch urlError.code {
                        case .timedOut:
                            throw TranslationError.networkTimeout
                        case .notConnectedToInternet:
                            throw TranslationError.noInternetConnection
                        default:
                            throw TranslationError.networkError
                        }
                    } else {
                        throw TranslationError.networkError
                    }
                }
                
                try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
            }
        }
        
        throw lastError ?? TranslationError.networkError
    }
    
    private func createTranslationPrompt(text: String, from sourceLanguage: String, to targetLanguage: String, customPrompt: TranslationPrompt?) -> String {
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
        
        let additionalInstructions = customPrompt?.userPromptAddition ?? ""
        
        return """
        \(sourceInstruction) на \(targetName) следующий текст. 
        Сохрани стиль, тон и форматирование оригинала. 
        \(additionalInstructions)
        Верни только переведённый текст без дополнительных пояснений или комментариев.
        
        Текст для перевода:
        \(text)
        """
    }
}

// MARK: - SettingsManager.swift (Управление настройками)
import Foundation
import SwiftUI

struct TranslationPrompt: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var icon: String
    var systemPrompt: String
    var userPromptAddition: String
}

// ДОБАВЛЕНО: Структура профиля подключения
struct ConnectionProfile: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var apiUrl: String
    var apiToken: String
    var modelName: String
    var temperature: Double = 0.3
    var maxTokens: Int = 1024
    var icon: String = "🌐"
    
    var isConfigured: Bool {
        !apiUrl.isEmpty && !apiToken.isEmpty && !modelName.isEmpty
    }
    
    var displayName: String {
        return "\(icon) \(name)"
    }
}

class SettingsManager: ObservableObject {
    @Published var connectionProfiles: [ConnectionProfile] = []
    @Published var activeProfileId: String = ""
    @Published var customPrompts: [TranslationPrompt] = []
    @Published var quickTranslateHotkey: String = "⌘⇧T"
    
    // Вычисляемые свойства для обратной совместимости
    var apiUrl: String {
        get { activeProfile?.apiUrl ?? "" }
        set { 
            if var profile = activeProfile {
                profile.apiUrl = newValue
                updateActiveProfile(profile)
            }
        }
    }
    
    var apiToken: String {
        get { activeProfile?.apiToken ?? "" }
        set { 
            if var profile = activeProfile {
                profile.apiToken = newValue
                updateActiveProfile(profile)
            }
        }
    }
    
    var modelName: String {
        get { activeProfile?.modelName ?? "" }
        set { 
            if var profile = activeProfile {
                profile.modelName = newValue
                updateActiveProfile(profile)
            }
        }
    }
    
    var temperature: Double {
        get { activeProfile?.temperature ?? 0.3 }
        set { 
            if var profile = activeProfile {
                profile.temperature = newValue
                updateActiveProfile(profile)
            }
        }
    }
    
    var maxTokens: Int {
        get { activeProfile?.maxTokens ?? 1024 }
        set { 
            if var profile = activeProfile {
                profile.maxTokens = newValue
                updateActiveProfile(profile)
            }
        }
    }
    
    var isConfigured: Bool {
        activeProfile?.isConfigured ?? false
    }
    
    var activeProfile: ConnectionProfile? {
        get {
            connectionProfiles.first { $0.id == activeProfileId }
        }
        set {
            if let newProfile = newValue {
                updateActiveProfile(newProfile)
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
        migrateOldSettings()
    }
    
    private func updateActiveProfile(_ profile: ConnectionProfile) {
        if let index = connectionProfiles.firstIndex(where: { $0.id == profile.id }) {
            connectionProfiles[index] = profile
        }
    }
    
    func loadSettings() {
        // Загружаем профили
        if let profilesData = userDefaults.data(forKey: "connectionProfiles"),
           let decodedProfiles = try? JSONDecoder().decode([ConnectionProfile].self, from: profilesData) {
            connectionProfiles = decodedProfiles
        }
        
        activeProfileId = userDefaults.string(forKey: "activeProfileId") ?? ""
        
        // Если нет активного профиля, но есть профили, выбираем первый
        if activeProfileId.isEmpty && !connectionProfiles.isEmpty {
            activeProfileId = connectionProfiles.first!.id
        }
        
        if let promptsData = userDefaults.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([TranslationPrompt].self, from: promptsData) {
            customPrompts = decodedPrompts
        }
        
        quickTranslateHotkey = userDefaults.string(forKey: "quickTranslateHotkey") ?? "⌘⇧T"
    }
    
    func saveSettings() {
        // Сохраняем профили
        if let encodedProfiles = try? JSONEncoder().encode(connectionProfiles) {
            userDefaults.set(encodedProfiles, forKey: "connectionProfiles")
        }
        
        userDefaults.set(activeProfileId, forKey: "activeProfileId")
        
        if let encodedPrompts = try? JSONEncoder().encode(customPrompts) {
            userDefaults.set(encodedPrompts, forKey: "customPrompts")
        }
        
        userDefaults.set(quickTranslateHotkey, forKey: "quickTranslateHotkey")
    }
    
    // Миграция старых настроек в профили
    private func migrateOldSettings() {
        let oldApiUrl = userDefaults.string(forKey: "apiUrl") ?? ""
        let oldApiToken = userDefaults.string(forKey: "apiToken") ?? ""
        let oldModelName = userDefaults.string(forKey: "modelName") ?? ""
        
        // Если есть старые настройки и нет профилей, создаем профиль по умолчанию
        if !oldApiUrl.isEmpty && !oldApiToken.isEmpty && !oldModelName.isEmpty && connectionProfiles.isEmpty {
            let savedTemperature = userDefaults.double(forKey: "temperature")
            let temperature = savedTemperature == 0 ? 0.3 : savedTemperature
            
            let savedMaxTokens = userDefaults.integer(forKey: "maxTokens")
            let maxTokens = savedMaxTokens == 0 ? 1024 : savedMaxTokens
            
            let defaultProfile = ConnectionProfile(
                name: "Основной профиль",
                apiUrl: oldApiUrl,
                apiToken: oldApiToken,
                modelName: oldModelName,
                temperature: temperature,
                maxTokens: maxTokens,
                icon: "🌐"
            )
            
            connectionProfiles = [defaultProfile]
            activeProfileId = defaultProfile.id
            
            // Удаляем старые ключи
            userDefaults.removeObject(forKey: "apiUrl")
            userDefaults.removeObject(forKey: "apiToken") 
            userDefaults.removeObject(forKey: "modelName")
            userDefaults.removeObject(forKey: "temperature")
            userDefaults.removeObject(forKey: "maxTokens")
            
            saveSettings()
        }
    }
    
    // MARK: - Методы для работы с профилями
    
    func addProfile(_ profile: ConnectionProfile) {
        connectionProfiles.append(profile)
        saveSettings()
    }
    
    func updateProfile(_ profile: ConnectionProfile) {
        if let index = connectionProfiles.firstIndex(where: { $0.id == profile.id }) {
            connectionProfiles[index] = profile
            saveSettings()
        }
    }
    
    func deleteProfile(_ profile: ConnectionProfile) {
        connectionProfiles.removeAll { $0.id == profile.id }
        
        // Если удаляем активный профиль, выбираем другой
        if activeProfileId == profile.id {
            activeProfileId = connectionProfiles.first?.id ?? ""
        }
        
        saveSettings()
    }
    
    func setActiveProfile(_ profileId: String) {
        if connectionProfiles.contains(where: { $0.id == profileId }) {
            activeProfileId = profileId
            saveSettings()
        }
    }
    
    func duplicateProfile(_ profile: ConnectionProfile) -> ConnectionProfile {
        let newProfile = ConnectionProfile(
            name: "\(profile.name) (Копия)",
            apiUrl: profile.apiUrl,
            apiToken: profile.apiToken,
            modelName: profile.modelName,
            temperature: profile.temperature,
            maxTokens: profile.maxTokens,
            icon: profile.icon
        )
        addProfile(newProfile)
        return newProfile
    }
    
    func resetToDefaults() {
        connectionProfiles = []
        activeProfileId = ""
        customPrompts = []
        quickTranslateHotkey = "⌘⇧T"
        saveSettings()
    }
    
    // MARK: - Примеры профилей
    
    func createExampleProfiles() -> [ConnectionProfile] {
        return [
            ConnectionProfile(
                name: "OpenAI GPT-4",
                apiUrl: "https://api.openai.com/v1",
                apiToken: "",
                modelName: "gpt-4o-mini",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🤖"
            ),
            ConnectionProfile(
                name: "Локальный Ollama",
                apiUrl: "http://localhost:11434/v1",
                apiToken: "ollama",
                modelName: "llama3.2:latest",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🦙"
            ),
            ConnectionProfile(
                name: "Claude (Anthropic)",
                apiUrl: "https://api.anthropic.com/v1",
                apiToken: "",
                modelName: "claude-3-haiku-20240307",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🧠"
            ),
            ConnectionProfile(
                name: "OpenRouter",
                apiUrl: "https://openrouter.ai/api/v1",
                apiToken: "",
                modelName: "meta-llama/llama-3.2-3b-instruct:free",
                temperature: 0.3,
                maxTokens: 1024,
                icon: "🚀"
            )
        ]
    }
}

// MARK: - TranslationError.swift (Обработка ошибок)
import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidRequest
    case networkError
    case networkTimeout
    case noInternetConnection
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
            return "Ошибка сети. Проверьте интернет соединение и попробуйте снова."
        case .networkTimeout:
            return "Превышено время ожидания ответа. Проверьте соединение и попробуйте снова."
        case .noInternetConnection:
            return "Нет подключения к интернету. Проверьте сетевые настройки."
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
