//
//  ButtonStyles.swift
//  AI Translator
//
//  Кастомные стили кнопок
//

import SwiftUI

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .blue.opacity(0.7) : .blue)
            .underline()
    }
}
