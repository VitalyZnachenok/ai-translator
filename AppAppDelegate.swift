//
//  AppDelegate.swift
//  AI Translator
//
//  Делегат приложения для управления menu bar, окнами и горячими клавишами
//

import SwiftUI
import AppKit
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    weak var settingsWindow: NSWindow?
    weak var mainWindow: NSWindow?
    var sharedSettingsManager = SettingsManager()
    
    // Event monitors
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    
    private let logger = Logger(subsystem: "com.vitaly.ai-translator", category: "AppDelegate")
    
    // MARK: - Lifecycle
    
    deinit {
        removeEventMonitors()
        stopGlobalHotkey()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application launched")
        setupMenuBar()
        setupHotKeys()
        requestAccessibilityPermissions()
        setupGlobalHotkey()
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating")
        removeEventMonitors()
        settingsWindow = nil
        mainWindow = nil
        popover = nil
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Menu Bar Setup

extension AppDelegate {
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
        guard let event = NSApp.currentEvent else { return }
        
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
        
        let hotkeyDisplay = sharedSettingsManager.quickTranslateHotkey
        let quickTranslateItem = NSMenuItem(
            title: "⚡ Перевести выделенный текст (\(hotkeyDisplay))",
            action: #selector(quickTranslateFromClipboard),
            keyEquivalent: ""
        )
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
}

// MARK: - Popover Management

extension AppDelegate {
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
        
        if let popover, popover.isShown {
            closePopover()
        } else {
            mainWindow?.close()
            settingsWindow?.close()
            
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.becomeKey()
        }
    }
    
    func closePopover() {
        popover?.performClose(nil)
    }
}

// MARK: - Window Management

extension AppDelegate {
    @objc func showMainWindow() {
        if let existingWindow = mainWindow, existingWindow.isVisible {
            logger.debug("Using existing main window")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        logger.debug("Creating new main window")
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
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        closePopover()
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Настройки AI Переводчика"
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 680, height: 800)
        newWindow.maxSize = NSSize(width: 900, height: 1000)
        
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
        Версия 1.4
        
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
    
    @objc func quit() {
        popover?.performClose(nil)
        settingsWindow?.close()
        mainWindow?.close()
        
        removeEventMonitors()
        
        NSApp.terminate(nil)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window == settingsWindow {
            settingsWindow = nil
        } else if window == mainWindow {
            mainWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
