//
//  ButtonStyles.swift
//  AI Translator
//
//  Кастомные стили кнопок
//

import SwiftUI

/// Подчёркнутая «ссылка». Имя отличается от системного SwiftUI LinkButtonStyle, чтобы не было путаницы.
struct UnderlinedLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .blue.opacity(0.7) : .blue)
            .underline()
    }
}
