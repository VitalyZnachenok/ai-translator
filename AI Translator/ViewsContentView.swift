//
//  ContentView.swift
//  AI Translator
//
//  Главное окно переводчика
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = TranslationViewModel()
    var settingsManager: SettingsManager
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            languageSelectionSection
            translationStyleSection
            inputSection
            translateButtonSection
            outputSection
            configurationWarning
            Spacer()
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settingsManager: settingsManager)
        }
        .alert("Ошибка", isPresented: $viewModel.showingError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
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
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "globe")
                .font(.title)
                .foregroundColor(.blue)
            Text("AI Переводчик")
                .font(.title)
                .fontWeight(.bold)
            
            Spacer()
            
            HStack(spacing: 8) {
                profileSelector
                connectionStatus
            }
            
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Настройки (⌘,)")
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var profileSelector: some View {
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
                HStack(spacing: 4) {
                    if let activeProfile = viewModel.activeProfile {
                        Text(activeProfile.icon)
                            .font(.caption)
                        Text(activeProfile.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Переключить профиль подключения")
        }
    }
    
    private var connectionStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isConfigured ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(viewModel.isConfigured ? "Подключено" : "Не настроено")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Language Selection Section
    
    private var languageSelectionSection: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("С какого языка:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Picker("Исходный язык", selection: $viewModel.selectedSourceLanguage) {
                    ForEach(LanguageData.fullLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 200)
            }
            
            Button(action: { viewModel.swapLanguages() }) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.selectedSourceLanguage == "auto")
            .help("Поменять языки местами")
            
            VStack(alignment: .leading) {
                Text("На какой язык:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Picker("Целевой язык", selection: $viewModel.selectedTargetLanguage) {
                    ForEach(LanguageData.fullLanguages.filter { $0.0 != "auto" }, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 200)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Translation Style Section
    
    private var translationStyleSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Стиль перевода:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Picker("Стиль", selection: $viewModel.selectedPromptId) {
                    Text("🎯 Стандартный").tag("default")
                    ForEach(viewModel.customPrompts) { prompt in
                        Text(prompt.icon + " " + prompt.name).tag(prompt.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(minWidth: 200)
            }
            
            Spacer()
            
            if let currentPrompt = viewModel.currentPrompt {
                Text(currentPrompt.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 300)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Текст для перевода:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.inputText.isEmpty {
                    Button(action: { viewModel.clearInput() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Очистить текст")
                }
                
                Text("\(viewModel.inputText.count)/5000")
                    .font(.caption)
                    .foregroundColor(viewModel.inputText.count > 4500 ? .red : .secondary)
            }
            
            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .frame(minHeight: 120, maxHeight: 200)
                .onChange(of: viewModel.inputText) { _, _ in
                    viewModel.validateInputLength()
                }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Translate Button Section
    
    private var translateButtonSection: some View {
        HStack(spacing: 12) {
            // Основная кнопка перевода
            Button(action: { viewModel.translate() }) {
                HStack {
                    if viewModel.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(viewModel.isTranslating ? "Переводим..." : "Перевести")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
                .shadow(radius: 2)
            }
            .disabled(!viewModel.canTranslate)
            .buttonStyle(PlainButtonStyle())
            .help("Перевести текст (⌘↩)")
            
            // Кнопка перевода с пояснениями
            Button(action: { viewModel.translateWithExplanation() }) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text("С пояснениями")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.orange, .pink]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
                .shadow(radius: 2)
            }
            .disabled(!viewModel.canTranslate)
            .buttonStyle(PlainButtonStyle())
            .help("Перевести с комментариями и объяснениями выбора слов")
            
            Text("⌘↩")
                .font(.caption)
                .foregroundColor(.secondary)
                .help("Нажмите Cmd+Enter для быстрого перевода")
            
            Button(action: { viewModel.pasteFromClipboard() }) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Вставить")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Вставить текст из буфера обмена")
            
            Button(action: { viewModel.clearAll() }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Очистить")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.inputText.isEmpty && viewModel.outputText.isEmpty)
            .help("Очистить ввод и результат")
        }
    }
    
    // MARK: - Output Section
    
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Результат перевода:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.outputText.isEmpty {
                    HStack(spacing: 8) {
                        Button(action: { viewModel.copyToClipboard() }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.copyFeedback ? "checkmark" : "doc.on.clipboard")
                                    .foregroundColor(viewModel.copyFeedback ? .green : .blue)
                                Text(viewModel.copyFeedback ? "Скопировано!" : "Копировать")
                                    .foregroundColor(viewModel.copyFeedback ? .green : .blue)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Копировать перевод в буфер обмена")
                        
                        Button(action: { viewModel.clearOutput() }) {
                            Image(systemName: "trash")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Очистить результат")
                    }
                }
            }
            
            ScrollView {
                Text(viewModel.formattedOutput)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 250)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Configuration Warning
    
    @ViewBuilder
    private var configurationWarning: some View {
        if !viewModel.isConfigured {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Настройте подключение к API в настройках")
                    .foregroundColor(.orange)
                
                Spacer()
                
                Button("Открыть настройки") {
                    showingSettings = true
                }
                .buttonStyle(UnderlinedLinkButtonStyle())
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}
