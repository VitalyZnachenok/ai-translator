//
//  CompactContentView.swift
//  AI Translator
//
//  Компактный вид для popover в menu bar
//

import SwiftUI
import AppKit

struct CompactContentView: View {
    @State private var viewModel = TranslationViewModel()
    var settingsManager: SettingsManager
    
    var body: some View {
        VStack(spacing: 12) {
            headerSection
            languageSelectionSection
            styleSelector
            inputSection
            translateButtons
            outputSection
            configurationWarning
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.configure(with: settingsManager)
            viewModel.setupKeyboardShortcuts()
            viewModel.setupQuickTranslateListener()
        }
        .onDisappear {
            viewModel.removeKeyboardShortcuts()
            viewModel.removeQuickTranslateListener()
        }
        .alert("Ошибка", isPresented: $viewModel.showingError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.blue)
            Text("AI Переводчик")
                .font(.headline)
                .fontWeight(.bold)
            
            Spacer()
            
            profileMenu
            
            Circle()
                .fill(viewModel.isConfigured ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            
            Button(action: openMainWindow) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Открыть полную версию (⌘O)")
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var profileMenu: some View {
        if !viewModel.connectionProfiles.isEmpty {
            Menu {
                ForEach(viewModel.connectionProfiles) { profile in
                    Button(action: {
                        viewModel.setActiveProfile(profile.id)
                    }) {
                        HStack {
                            Text(profile.displayName)
                            if viewModel.activeProfileId == profile.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                if let activeProfile = viewModel.activeProfile {
                    Text(activeProfile.icon)
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Переключить профиль")
        }
    }
    
    // MARK: - Language Selection Section
    
    private var languageSelectionSection: some View {
        HStack(spacing: 8) {
            Picker("От", selection: $viewModel.selectedSourceLanguage) {
                ForEach(LanguageData.compactLanguages, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 120)
            
            Button(action: { viewModel.swapLanguages() }) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.selectedSourceLanguage == "auto")
            
            Picker("В", selection: $viewModel.selectedTargetLanguage) {
                ForEach(LanguageData.compactLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 120)
            
            Spacer()
            
            Button(action: { viewModel.pasteFromClipboard() }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Вставить из буфера")
        }
        .padding(.horizontal)
    }
    
    // MARK: - Style Selector
    
    @ViewBuilder
    private var styleSelector: some View {
        if !viewModel.customPrompts.isEmpty {
            HStack {
                Picker("Стиль", selection: $viewModel.selectedPromptId) {
                    Text("🎯").tag("default")
                    ForEach(viewModel.customPrompts) { prompt in
                        Text(prompt.icon).tag(prompt.id)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Текст:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.inputText.isEmpty {
                    Button(action: { viewModel.clearInput() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Text("\(viewModel.inputText.count)/5000")
                    .font(.caption2)
                    .foregroundColor(viewModel.inputText.count > 4500 ? .red : .secondary)
            }
            
            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 12))
                .padding(6)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .frame(minHeight: 80, maxHeight: 120)
                .onChange(of: viewModel.inputText) { _, _ in
                    viewModel.validateInputLength()
                }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Translate Buttons
    
    private var translateButtons: some View {
        HStack(spacing: 8) {
            // Основная кнопка перевода
            Button(action: { viewModel.translate() }) {
                HStack {
                    if viewModel.isTranslating {
                        ProgressView()
                            .controlSize(.mini)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(viewModel.isTranslating ? "..." : "Перевести")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(6)
            }
            .disabled(!viewModel.canTranslate)
            .buttonStyle(PlainButtonStyle())
            .help("Перевести текст (⌘↩)")
            
            // Кнопка перевода с пояснениями
            Button(action: { viewModel.translateWithExplanation() }) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text("📝")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.orange, .pink]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(6)
            }
            .disabled(!viewModel.canTranslate)
            .buttonStyle(PlainButtonStyle())
            .help("Перевести с пояснениями")
            
            Button(action: { viewModel.clearAll() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.inputText.isEmpty && viewModel.outputText.isEmpty)
            .help("Очистить всё")
        }
    }
    
    // MARK: - Output Section
    
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Результат:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.outputText.isEmpty {
                    Button(action: { viewModel.copyToClipboard() }) {
                        Image(systemName: viewModel.copyFeedback ? "checkmark" : "doc.on.clipboard")
                            .font(.caption)
                            .foregroundColor(viewModel.copyFeedback ? .green : .blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Копировать")
                }
            }
            
            ScrollView {
                Text(viewModel.formattedOutput)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 80, maxHeight: 150)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Configuration Warning
    
    @ViewBuilder
    private var configurationWarning: some View {
        if !viewModel.isConfigured {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
                Text("Настройте подключение")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                Spacer()
                
                Button("Настройки") {
                    openSettings()
                }
                .font(.caption2)
                .buttonStyle(UnderlinedLinkButtonStyle())
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Actions
    
    private func openMainWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showMainWindow()
        }
    }
    
    private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showSettings()
        }
    }
}
