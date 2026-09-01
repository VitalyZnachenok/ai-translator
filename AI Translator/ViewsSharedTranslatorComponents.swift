//
//  ViewsSharedTranslatorComponents.swift
//  AI Translator
//
//  Куски UI и модификаторы, идентичные по логике в ContentView и CompactContentView.
//  Вынесены сюда, чтобы изменение поведения (не оформления) требовалось внести один раз.
//

import SwiftUI

// MARK: - Profile Picker Menu

/// Меню выбора активного профиля подключения. Внешний вид заголовка (`label`)
/// задаётся вызывающей стороной — в полном и компактном окне он оформлен по-разному.
struct ProfilePickerMenu<Label: View>: View {
    let profiles: [ConnectionProfile]
    let activeProfileId: String
    let onSelect: (String) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if !profiles.isEmpty {
            Menu {
                ForEach(profiles) { profile in
                    Button(action: { onSelect(profile.id) }) {
                        HStack {
                            Text(profile.displayName)
                            if activeProfileId == profile.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
            .help("Переключить профиль подключения")
        }
    }
}

// MARK: - Input Character Counter

/// Счётчик длины введённого текста с подсветкой красным при приближении к лимиту.
struct InputCharacterCountLabel: View {
    let count: Int
    let limit: Int
    var font: Font = .caption

    var body: some View {
        Text("\(count)/\(limit)")
            .font(font)
            .foregroundColor(count > Int(Double(limit) * 0.9) ? .red : .secondary)
    }
}

// MARK: - Translation Lifecycle & Error Alert

private struct TranslationLifecycleModifier: ViewModifier {
    let viewModel: TranslationViewModel
    let settingsManager: SettingsManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                viewModel.configure(with: settingsManager)
                viewModel.setupKeyboardShortcuts()
                viewModel.setupQuickTranslateListener()
            }
            .onDisappear {
                viewModel.removeKeyboardShortcuts()
                viewModel.removeQuickTranslateListener()
            }
    }
}

private struct TranslationErrorAlertModifier: ViewModifier {
    @Bindable var viewModel: TranslationViewModel

    func body(content: Content) -> some View {
        content.alert("Ошибка", isPresented: $viewModel.showingError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

extension View {
    /// Настраивает ViewModel и вешает/снимает хоткей-мониторы при появлении/исчезновении вью.
    func translationLifecycle(viewModel: TranslationViewModel, settingsManager: SettingsManager) -> some View {
        modifier(TranslationLifecycleModifier(viewModel: viewModel, settingsManager: settingsManager))
    }

    /// Показывает alert с ошибкой перевода, если она возникла.
    func translationErrorAlert(_ viewModel: TranslationViewModel) -> some View {
        modifier(TranslationErrorAlertModifier(viewModel: viewModel))
    }
}
