//
//  PromptEditView.swift
//  AI Translator
//
//  Редактор кастомных промптов для стилей перевода
//

import SwiftUI

struct PromptEditView: View {
    let prompt: TranslationPrompt?
    let onSave: (TranslationPrompt) -> Void
    
    @State private var name = ""
    @State private var description = ""
    @State private var icon = "✨"
    @State private var systemPrompt = ""
    @State private var userPromptAddition = ""
    @Environment(\.dismiss) private var dismiss
    
    private let availableIcons = ["✨", "💬", "📚", "⚙️", "💼", "🎯", "🔥", "💡", "🎨", "🚀", "📝", "🌟"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text(prompt == nil ? "Новый стиль перевода" : "Редактировать стиль")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                Section("Основная информация") {
                    HStack {
                        Text("Иконка:")
                        Picker("", selection: $icon) {
                            ForEach(availableIcons, id: \.self) { emoji in
                                Text(emoji).tag(emoji)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    TextField("Название стиля", text: $name)
                    TextField("Краткое описание", text: $description)
                }
                
                Section("Настройки промпта") {
                    VStack(alignment: .leading) {
                        Text("Системный промпт:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12))
                            .frame(height: 80)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Дополнение к запросу пользователя:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $userPromptAddition)
                            .font(.system(size: 12))
                            .frame(height: 60)
                    }
                }
            }
            
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Сохранить") {
                    let newPrompt = TranslationPrompt(
                        id: prompt?.id ?? UUID().uuidString,
                        name: name,
                        description: description,
                        icon: icon,
                        systemPrompt: systemPrompt,
                        userPromptAddition: userPromptAddition
                    )
                    onSave(newPrompt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || systemPrompt.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            if let prompt = prompt {
                name = prompt.name
                description = prompt.description
                icon = prompt.icon
                systemPrompt = prompt.systemPrompt
                userPromptAddition = prompt.userPromptAddition
            }
        }
    }
}
