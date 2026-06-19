//
//  AppDelegate+Hotkeys.swift
//  AI Translator
//
//  Расширение для работы с горячими клавишами
//

import AppKit
import Foundation
import os

/// Какая горячая клавиша была сопоставлена при перехвате события.
enum MatchedHotkey {
    case openTranslator
    case inPlace
}

// MARK: - Hotkey Management

extension AppDelegate {
    static let hotkeyLogger = Logger(subsystem: "com.vitaly.ai-translator", category: "Hotkeys")
    
    func setupHotKeys() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyEvent(event) {
                return nil
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.popover?.isShown == true {
                self.closePopover()
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: .hotkeyChanged,
            object: nil
        )
    }
    
    @objc func hotkeyChanged() {
        setupGlobalHotkey()
    }
    
    func removeEventMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        NotificationCenter.default.removeObserver(self, name: .hotkeyChanged, object: nil)
    }
    
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        
        switch event.charactersIgnoringModifiers {
        case ",":
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
            return true
        case "o":
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return true
        case "q":
            DispatchQueue.main.async { [weak self] in
                self?.quit()
            }
            return true
        default:
            return false
        }
    }
}

// MARK: - Global Hotkey Setup

extension AppDelegate {
    func requestAccessibilityPermissions() {
        // prompt: false — не показываем системный диалог, чтобы не дублировать собственное окно ниже.
        // Сам вызов всё равно регистрирует приложение в списке «Универсальный доступ».
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = String(localized: "Требуется разрешение")
            alert.informativeText = String(localized: """
            Для использования глобальных горячих клавиш приложению требуется доступ к универсальному доступу.
            
            Пожалуйста, добавьте AI Переводчик в:
            Системные настройки → Защита и безопасность → Конфиденциальность → Универсальный доступ
            """)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Открыть настройки"))
            alert.addButton(withTitle: String(localized: "Позже"))
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    /// Перечитывает строки хоткеев в кэш (keyCode + модификаторы). Вызывать при старте и изменении настроек.
    func refreshHotkeyCache() {
        cachedQuickHotkey = parseHotkeyString(sharedSettingsManager.quickTranslateHotkey)
        cachedInPlaceHotkey = parseHotkeyString(sharedSettingsManager.inPlaceTranslateHotkey)
    }

    /// Запускает периодические попытки активировать хоткеи, если они ещё не активны.
    /// Покрывает два случая: (1) доступ к Accessibility ещё не выдан; (2) `AXIsProcessTrusted()`
    /// возвращает true, но `CGEvent.tapCreate` не создаёт tap (типично после переустановки/переподписи,
    /// когда разрешение «протухло»). В обоих случаях хоткеи активируются сразу после исправления —
    /// без перезапуска приложения.
    func startAccessibilityMonitoringIfNeeded() {
        guard eventTap == nil else { return }
        startHotkeyRetryTimer()
    }

    private func startHotkeyRetryTimer() {
        guard accessibilityPollTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.eventTap != nil {
                self.stopAccessibilityMonitoring()
                return
            }
            self.setupGlobalHotkey()
        }
        timer.tolerance = 0.5
        accessibilityPollTimer = timer
    }

    func stopAccessibilityMonitoring() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    /// Создаёт глобальный event tap. Возвращает true, если tap успешно активирован.
    @discardableResult
    func setupGlobalHotkey() -> Bool {
        stopGlobalHotkey()

        refreshHotkeyCache()

        guard AXIsProcessTrusted() else {
            Self.hotkeyLogger.warning("Accessibility not granted")
            startHotkeyRetryTimer()
            return false
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

                // Система может отключить tap, если callback подвисает. Реактивируем его.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = appDelegate.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                if let matched = appDelegate.matchedHotkey(event: event) {
                    DispatchQueue.main.async { [weak appDelegate] in
                        switch matched {
                        case .openTranslator:
                            appDelegate?.quickTranslateFromClipboard()
                        case .inPlace:
                            appDelegate?.inPlaceTranslate()
                        }
                    }
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            // AXIsProcessTrusted() вернул true, но tap создать не удалось — характерный признак
            // «протухшего» разрешения Accessibility (после обновления/переподписи приложения).
            // Показываем подсказку один раз и продолжаем периодически пытаться — хоткеи поднимутся,
            // как только пользователь переоткроет доступ.
            Self.hotkeyLogger.error("Failed to create event tap despite trusted status (stale Accessibility grant?)")
            notifyAccessibilityStaleIfNeeded()
            startHotkeyRetryTimer()
            return false
        }
        
        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Self.hotkeyLogger.error("Failed to create run loop source for event tap")
            stopGlobalHotkey()
            startHotkeyRetryTimer()
            return false
        }
        runLoopSource = source
        // Источник вешаем на выделенный поток, а НЕ на главный: иначе занятость главного потока
        // подвешивает доставку всех нажатий в системе (см. комментарий к tapThread).
        installSourceOnTapThread(source)
        CGEvent.tapEnable(tap: tap, enable: true)
        stopAccessibilityMonitoring()
        
        Self.hotkeyLogger.info("Global hotkey enabled")
        return true
    }

    /// Создаёт (при необходимости) выделенный поток с собственным run loop и вешает на него
    /// источник event tap. Поток живёт всё время работы приложения и переживает пересоздания tap.
    private func installSourceOnTapThread(_ source: CFRunLoopSource) {
        if let runLoop = tapRunLoop {
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CFRunLoopWakeUp(runLoop)
            return
        }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            ready.signal()
            // Держим run loop живым даже когда источник временно снят (при пересоздании tap).
            // Таймаут лишь ограничивает частоту проверки isCancelled; на приход события
            // run loop просыпается немедленно, так что задержки обработки клавиш нет.
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.5, false)
            }
        }
        thread.name = "com.vitaly.ai-translator.eventtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        // Дожидаемся, пока поток зафиксирует свой run loop и повесит источник.
        ready.wait()
    }

    /// Останавливает выделенный поток event tap (при выходе из приложения).
    func teardownTapThread() {
        tapThread?.cancel()
        if let runLoop = tapRunLoop {
            CFRunLoopWakeUp(runLoop)
        }
        tapThread = nil
        tapRunLoop = nil
    }

    /// Подсказка пользователю, когда доступ формально есть, но tap не создаётся.
    private func notifyAccessibilityStaleIfNeeded() {
        guard !accessibilityAlertShown else { return }
        accessibilityAlertShown = true

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = String(localized: "Горячие клавиши недоступны")
            alert.informativeText = String(localized: """
            Системе не удалось активировать глобальные горячие клавиши, хотя доступ к универсальному доступу отмечен как выданный. Обычно это происходит после обновления приложения.

            Откройте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ, выключите и снова включите AI Translator (или удалите и добавьте заново). Хоткеи активируются автоматически.
            """)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Открыть настройки"))
            alert.addButton(withTitle: String(localized: "Позже"))

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    func stopGlobalHotkey() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource, let runLoop = tapRunLoop {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
                CFRunLoopWakeUp(runLoop)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
    
    func checkHotkey(event: CGEvent) -> Bool {
        matchedHotkey(event: event) == .openTranslator
    }

    /// Сопоставляет событие клавиатуры с одним из настроенных хоткеев, используя кэш.
    /// Если совпали оба (одинаковая комбинация), приоритет — у in-place перевода, поскольку он применяется в активном поле.
    func matchedHotkey(event: CGEvent) -> MatchedHotkey? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        var currentModifiers: CGEventFlags = []
        if flags.contains(.maskCommand) { currentModifiers.insert(.maskCommand) }
        if flags.contains(.maskShift) { currentModifiers.insert(.maskShift) }
        if flags.contains(.maskAlternate) { currentModifiers.insert(.maskAlternate) }
        if flags.contains(.maskControl) { currentModifiers.insert(.maskControl) }

        if sharedSettingsManager.inPlaceEnabled,
           keyCode == cachedInPlaceHotkey.keyCode,
           currentModifiers == cachedInPlaceHotkey.modifiers {
            return .inPlace
        }

        if keyCode == cachedQuickHotkey.keyCode,
           currentModifiers == cachedQuickHotkey.modifiers {
            return .openTranslator
        }

        return nil
    }
    
    func parseHotkeyString(_ hotkey: String) -> (keyCode: Int64, modifiers: CGEventFlags) {
        var modifiers: CGEventFlags = []

        if hotkey.contains("⌘") { modifiers.insert(.maskCommand) }
        if hotkey.contains("⇧") { modifiers.insert(.maskShift) }
        if hotkey.contains("⌥") { modifiers.insert(.maskAlternate) }
        if hotkey.contains("⌃") { modifiers.insert(.maskControl) }

        // Убираем символы модификаторов — остаётся метка клавиши (может быть многосимвольной, например "Space").
        let keyLabel = hotkey
            .replacingOccurrences(of: "⌘", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⌃", with: "")

        let keyCode = Int64(KeyCodeMapper.keyCodeForKeyLabel(keyLabel))

        return (keyCode, modifiers)
    }
}

// MARK: - Quick Translation

extension AppDelegate {
    @objc func quickTranslateFromClipboard() {
        Self.hotkeyLogger.debug("Quick translate triggered")

        Task { @MainActor [weak self] in
            guard let self else { return }

            let pasteboard = NSPasteboard.general
            let oldClipboard = pasteboard.string(forType: .string)

            // Сначала дожидаемся, пока пользователь отпустит модификаторы хоткея,
            // иначе синтетический ⌘C объединится с зажатым ⇧ и станет ⌘⇧C (не «Копировать»).
            await self.waitForModifierKeysReleased()

            pasteboard.clearContents()
            // Базовый счётчик снимаем ПОСЛЕ clearContents(): сам clearContents() увеличивает
            // changeCount, поэтому если снять до — ожидание сработает мгновенно, не дождавшись копии.
            let baselineChangeCount = pasteboard.changeCount
            self.simulateCopy()

            // Ждём реального изменения буфера вместо фиксированной задержки.
            let copied = await self.waitForClipboardChange(initial: baselineChangeCount, timeout: 1.0)

            guard copied, let text = pasteboard.string(forType: .string), !text.isEmpty else {
                await self.restoreClipboard(oldClipboard)
                Self.hotkeyLogger.warning("No text selected for translation")
                self.notifyError(title: String(localized: "Нет выделенного текста"),
                                 message: String(localized: "Выделите текст для перевода и попробуйте снова"))
                return
            }

            Self.hotkeyLogger.debug("Text copied for translation: \(text.prefix(50))...")

            UserDefaults.standard.set(text, forKey: "pendingTranslationText")

            self.showMainWindow()

            try? await Task.sleep(for: .milliseconds(500))

            NotificationCenter.default.post(
                name: .quickTranslateText,
                object: nil,
                userInfo: ["text": text]
            )

            // Восстанавливаем буфер обмена.
            if let oldText = oldClipboard, oldText != text {
                try? await Task.sleep(for: .seconds(1))
                await self.restoreClipboard(oldText)
            }
        }
    }
    
    private func simulateCopy() {
        postModifiedKey(virtualKey: 0x08) // C
    }

    private func simulatePaste() {
        postModifiedKey(virtualKey: 0x09) // V
    }

    private func postModifiedKey(virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)

        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cgAnnotatedSessionEventTap)
        }

        if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) {
            keyUpEvent.flags = .maskCommand
            keyUpEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

// MARK: - In-Place Translation

extension AppDelegate {
    /// Переводит выделенный текст в активном окне "на месте" — заменяет его переведённым через буфер обмена.
    /// Повторное нажатие хоткея во время выполнения отменяет операцию и восстанавливает буфер.
    @objc func inPlaceTranslate() {
        // Если задача уже выполняется — повторное нажатие отменяет её.
        // Сама задача обнулит inPlaceTask, когда завершится, поэтому новый запуск возможен только после полного завершения.
        if let existing = inPlaceTask {
            if !existing.isCancelled {
                Self.hotkeyLogger.info("In-place translation cancelled by repeated hotkey")
                existing.cancel()
                setMenuBarStatus(.idle)
            }
            return
        }

        guard sharedSettingsManager.inPlaceEnabled else {
            Self.hotkeyLogger.debug("In-place translation disabled in settings")
            return
        }

        guard sharedSettingsManager.isConfigured else {
            notifyError(title: String(localized: "Перевод не настроен"),
                        message: String(localized: "Сначала настройте профиль подключения в окне настроек."))
            return
        }

        inPlaceTask = Task { @MainActor [weak self] in
            await self?.runInPlaceTranslation()
            self?.inPlaceTask = nil
        }
    }

    @MainActor
    private func runInPlaceTranslation() async {
        Self.hotkeyLogger.debug("In-place translation started")

        let pasteboard = NSPasteboard.general
        let originalText = pasteboard.string(forType: .string)

        setMenuBarStatus(.busy)

        // Дожидаемся, пока пользователь отпустит модификаторы хоткея, иначе
        // синтетический ⌘C объединится с зажатым ⇧ и станет ⌘⇧C (не «Копировать»).
        await waitForModifierKeysReleased()

        // 1. Симулируем Cmd+C и ждём, пока буфер реально обновится.
        let originalChangeCount = pasteboard.changeCount
        simulateCopy()
        let copied = await waitForClipboardChange(initial: originalChangeCount, timeout: 1.0)

        if Task.isCancelled {
            await restoreClipboard(originalText)
            setMenuBarStatus(.idle)
            return
        }

        guard copied, let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty else {
            await restoreClipboard(originalText)
            setMenuBarStatus(.error)
            notifyError(title: String(localized: "Нет выделенного текста"),
                        message: String(localized: "Выделите текст для перевода и попробуйте снова."))
            return
        }

        Self.hotkeyLogger.debug("In-place: captured text length=\(selectedText.count)")

        // 2. Выполняем перевод. Передаём текст, чтобы при включённом auto-swap корректно определилось направление.
        let resolved = sharedSettingsManager.resolvedInPlaceSettings(for: selectedText)
        switch resolved.direction {
        case .autoSwap(let detected):
            Self.hotkeyLogger.debug("In-place: auto-swap detected=\(detected), direction \(resolved.source)→\(resolved.target)")
        case .customSettings:
            Self.hotkeyLogger.debug("In-place: using custom settings \(resolved.source)→\(resolved.target)")
        case .lastUsed:
            Self.hotkeyLogger.debug("In-place: using last-used \(resolved.source)→\(resolved.target)")
        }

        let translated: String
        do {
            translated = try await sharedTranslationService.translate(
                text: selectedText,
                from: resolved.source,
                to: resolved.target,
                customPrompt: resolved.prompt
            )
        } catch is CancellationError {
            await restoreClipboard(originalText)
            setMenuBarStatus(.idle)
            return
        } catch {
            await restoreClipboard(originalText)
            setMenuBarStatus(.error)
            notifyError(title: String(localized: "Ошибка перевода"), message: error.localizedDescription)
            return
        }

        if Task.isCancelled {
            await restoreClipboard(originalText)
            setMenuBarStatus(.idle)
            return
        }

        // 3. Кладём перевод в буфер и симулируем Cmd+V.
        let beforePaste = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(translated, forType: .string)
        simulatePaste()

        let pasted = await waitForClipboardChange(initial: beforePaste, timeout: 1.0)
        if !pasted {
            // Не смогли подтвердить вставку — оставляем перевод в буфере, чтобы пользователь мог вставить вручную.
            setMenuBarStatus(.error)
            notifyError(title: String(localized: "Не удалось вставить перевод"),
                        message: String(localized: "Перевод скопирован в буфер обмена — попробуйте вставить вручную (⌘V)."))
            return
        }

        // 4. Восстанавливаем оригинальный буфер обмена через небольшую паузу.
        try? await Task.sleep(for: .milliseconds(400))
        await restoreClipboard(originalText)

        TranslationHistoryStore.shared.add(
            sourceText: selectedText,
            translatedText: translated,
            sourceLanguage: resolved.source,
            targetLanguage: resolved.target,
            origin: "Перевод на месте"
        )

        setMenuBarStatus(.success)
        Self.hotkeyLogger.info("In-place translation completed")
    }

    // MARK: - Helpers

    /// Дожидается, пока пользователь отпустит модификаторы хоткея (⌘/⇧/⌥/⌃),
    /// чтобы синтезированный ⌘C не объединился с зажатым ⇧ и не превратился в ⌘⇧C.
    /// Ограничено таймаутом — если клавиши держат дольше, всё равно продолжаем.
    private func waitForModifierKeysReleased(timeout: TimeInterval = 0.6) async {
        let watched: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return }
            let current = CGEventSource.flagsState(.combinedSessionState)
            if current.intersection(watched).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Ждёт, пока NSPasteboard.changeCount превысит исходное значение, что означает, что система действительно обновила буфер.
    private func waitForClipboardChange(initial: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if NSPasteboard.general.changeCount > initial { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return NSPasteboard.general.changeCount > initial
    }

    private func restoreClipboard(_ original: String?) async {
        guard let original else { return }
        // Даём системе устаканиться, чтобы не перезаписать вставку до того, как принимающее приложение её обработает.
        try? await Task.sleep(for: .milliseconds(50))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(original, forType: .string)
        Self.hotkeyLogger.debug("Clipboard restored")
    }

    private func notifyError(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Menu Bar Feedback

    enum InPlaceStatus {
        case idle, busy, success, error
    }

    private func setMenuBarStatus(_ status: InPlaceStatus) {
        guard let button = statusBarItem?.button else { return }

        let symbol: String
        switch status {
        case .idle:
            button.image = defaultStatusBarImage
            return
        case .busy:
            symbol = "arrow.triangle.2.circlepath"
        case .success:
            symbol = "checkmark.circle"
        case .error:
            symbol = "exclamationmark.triangle"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }

        // Авто-сброс иконки для terminal-состояний.
        if status == .success || status == .error {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.setMenuBarStatus(.idle)
            }
        }
    }
}
