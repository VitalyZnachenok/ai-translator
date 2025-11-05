//
//  ProfileCard.swift
//  AI Translator
//
//  Карточка профиля подключения
//

import SwiftUI

struct ProfileCard: View {
    let profile: ConnectionProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.icon)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(profile.modelName.isEmpty ? "Модель не выбрана" : profile.modelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            
            HStack {
                Circle()
                    .fill(profile.isConfigured ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(profile.isConfigured ? "Настроен" : "Не настроен")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Button("Редактировать") {
                        onEdit()
                    }
                    
                    Button("Дублировать") {
                        onDuplicate()
                    }
                    
                    Divider()
                    
                    Button("Удалить", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
    }
}
