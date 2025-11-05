//
//  AppDelegate+Hotkeys.swift
//  AI Translator
//
//  Расширение для работы с горячими клавишами
//

import AppKit
import Foundation

// MARK: - Hotkey Management

extension AppDelegate {
    func setupHotKeys() {
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
    }
    
    func handleKeyEvent(_ event: NSEvent) -> Bool {
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
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
    
    func setupGlobalHotkey() {
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
        print("🔥 quickTranslateFromClipboard called")
        
        let oldClipboard = NSPasteboard.general.string(forType: .string)
        print("📋 Old clipboard: \(oldClipboard?.prefix(50) ?? "nil")")
        
        NSPasteboard.general.clearContents()
        simulateCopy()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                print("❌ No text copied from selection")
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
            
            print("✅ Text copied: \(text.prefix(50))")
            
            UserDefaults.standard.set(text, forKey: "pendingTranslationText")
            UserDefaults.standard.synchronize()
            print("💾 Text saved to UserDefaults")
            
            self.showMainWindow()
            print("🪟 Main window shown")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📤 Posting QuickTranslateText notification")
                NotificationCenter.default.post(
                    name: Notification.Name("QuickTranslateText"),
                    object: nil,
                    userInfo: ["text": text]
                )
                
                if let oldText = oldClipboard, oldText != text {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(oldText, forType: .string)
                        print("♻️ Old clipboard restored")
                    }
                }
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
