//
//  AppDelegate+Hotkeys.swift
//  AI Translator
//
//  Расширение для работы с горячими клавишами
//

import AppKit
import Foundation
import os

// MARK: - Hotkey Management

extension AppDelegate {
    private static let hotkeyLogger = Logger(subsystem: "com.vitaly.ai-translator", category: "Hotkeys")
    
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
                
                if appDelegate.checkHotkey(event: event) {
                    DispatchQueue.main.async { [weak appDelegate] in
                        appDelegate?.quickTranslateFromClipboard()
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
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        let hotkeyString = sharedSettingsManager.quickTranslateHotkey
        let (savedKeyCode, savedModifiers) = parseHotkeyString(hotkeyString)
        
        var currentModifiers: CGEventFlags = []
        if flags.contains(.maskCommand) { currentModifiers.insert(.maskCommand) }
        if flags.contains(.maskShift) { currentModifiers.insert(.maskShift) }
        if flags.contains(.maskAlternate) { currentModifiers.insert(.maskAlternate) }
        if flags.contains(.maskControl) { currentModifiers.insert(.maskControl) }
        
        return keyCode == savedKeyCode && currentModifiers == savedModifiers
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
        let source = CGEventSource(stateID: .combinedSessionState)
        
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) {
            keyUpEvent.flags = .maskCommand
            keyUpEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
