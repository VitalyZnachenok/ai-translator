//
//  NotificationNames.swift
//  AI Translator
//
//  Централизованные имена внутренних уведомлений, чтобы не дублировать строковые литералы.
//

import Foundation

extension Notification.Name {
    /// Изменилась горячая клавиша — нужно перенастроить глобальный хоткей.
    static let hotkeyChanged = Notification.Name("HotkeyChanged")
    /// Запрошен быстрый перевод выделенного текста (с открытием окна).
    static let quickTranslateText = Notification.Name("QuickTranslateText")
}
