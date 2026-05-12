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
            name: Notification.Name("HotkeyChanged"),
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
        
        NotificationCenter.default.removeObserver(self, name: Notification.Name("HotkeyChanged"), object: nil)
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
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    func setupGlobalHotkey() {
        stopGlobalHotkey()
        
        guard AXIsProcessTrusted() else {
            Self.hotkeyLogger.warning("Accessibility not granted")
            return
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
            Self.hotkeyLogger.error("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        Self.hotkeyLogger.info("Global hotkey enabled")
    }
    
    func stopGlobalHotkey() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
    
    func checkHotkey(event: CGEvent) -> Bool {
        matchedHotkey(event: event) == .openTranslator
    }

    /// Сопоставляет событие клавиатуры с одним из настроенных хоткеев.
    /// Если совпали оба (одинаковая комбинация), приоритет — у in-place перевода, поскольку он применяется в активном поле.
    func matchedHotkey(event: CGEvent) -> MatchedHotkey? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        var currentModifiers: CGEventFlags = []
        if flags.contains(.maskCommand) { currentModifiers.insert(.maskCommand) }
        if flags.contains(.maskShift) { currentModifiers.insert(.maskShift) }
        if flags.contains(.maskAlternate) { currentModifiers.insert(.maskAlternate) }
        if flags.contains(.maskControl) { currentModifiers.insert(.maskControl) }

        if sharedSettingsManager.inPlaceEnabled {
            let (ipKey, ipMods) = parseHotkeyString(sharedSettingsManager.inPlaceTranslateHotkey)
            if keyCode == ipKey && currentModifiers == ipMods {
                return .inPlace
            }
        }

        let (qKey, qMods) = parseHotkeyString(sharedSettingsManager.quickTranslateHotkey)
        if keyCode == qKey && currentModifiers == qMods {
            return .openTranslator
        }

        return nil
    }
    
    func parseHotkeyString(_ hotkey: String) -> (Int64, CGEventFlags) {
        var modifiers: CGEventFlags = []
        var keyCode: Int64 = 0x11 // T по умолчанию
        
        if hotkey.contains("⌘") { modifiers.insert(.maskCommand) }
        if hotkey.contains("⇧") { modifiers.insert(.maskShift) }
        if hotkey.contains("⌥") { modifiers.insert(.maskAlternate) }
        if hotkey.contains("⌃") { modifiers.insert(.maskControl) }
        
        if let lastChar = hotkey.last {
            keyCode = Int64(KeyCodeMapper.keyCodeForCharacter(lastChar))
        }
        
        return (keyCode, modifiers)
    }
}

// MARK: - Quick Translation

extension AppDelegate {
    @objc func quickTranslateFromClipboard() {
        Self.hotkeyLogger.debug("Quick translate triggered")
        
        let oldClipboard = NSPasteboard.general.string(forType: .string)
        
        NSPasteboard.general.clearContents()
        simulateCopy()
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            try? await Task.sleep(for: .milliseconds(200))
            
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                // Восстанавливаем буфер обмена если текст не был скопирован
                if let oldText = oldClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(oldText, forType: .string)
                }
                
                Self.hotkeyLogger.warning("No text selected for translation")
                
                let alert = NSAlert()
                alert.messageText = "Нет выделенного текста"
                alert.informativeText = "Выделите текст для перевода и попробуйте снова"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            
            Self.hotkeyLogger.debug("Text copied for translation: \(text.prefix(50))...")
            
            UserDefaults.standard.set(text, forKey: "pendingTranslationText")
            
            self.showMainWindow()
            
            try? await Task.sleep(for: .milliseconds(500))
            
            NotificationCenter.default.post(
                name: Notification.Name("QuickTranslateText"),
                object: nil,
                userInfo: ["text": text]
            )
            
            // Восстанавливаем буфер обмена
            if let oldText = oldClipboard, oldText != text {
                try? await Task.sleep(for: .seconds(1))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(oldText, forType: .string)
                Self.hotkeyLogger.debug("Clipboard restored")
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
            notifyError(title: "Перевод не настроен",
                        message: "Сначала настройте профиль подключения в окне настроек.")
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
        let originalChangeCount = pasteboard.changeCount
        let originalText = pasteboard.string(forType: .string)

        setMenuBarStatus(.busy)

        // 1. Симулируем Cmd+C и ждём, пока буфер реально обновится.
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
            notifyError(title: "Нет выделенного текста",
                        message: "Выделите текст для перевода и попробуйте снова.")
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
            notifyError(title: "Ошибка перевода", message: error.localizedDescription)
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
            notifyError(title: "Не удалось вставить перевод",
                        message: "Перевод скопирован в буфер обмена — попробуйте вставить вручную (⌘V).")
            return
        }

        // 4. Восстанавливаем оригинальный буфер обмена через небольшую паузу.
        try? await Task.sleep(for: .milliseconds(400))
        await restoreClipboard(originalText)
        setMenuBarStatus(.success)
        Self.hotkeyLogger.info("In-place translation completed")
    }

    // MARK: - Helpers

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
