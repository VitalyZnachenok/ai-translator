//
//  HistoryView.swift
//  AI Translator
//
//  Окно истории переводов.
//

import SwiftUI
import AppKit

struct HistoryView: View {
    @State private var store = TranslationHistoryStore.shared
    let onClose: (() -> Void)?

    @State private var searchText = ""

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var filteredEntries: [TranslationHistoryEntry] {
        guard !searchText.isEmpty else { return store.entries }
        let query = searchText.lowercased()
        return store.entries.filter {
            $0.sourceText.lowercased().contains(query) ||
            $0.translatedText.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(width: 640, height: 680)
    }

    private var header: some View {
        HStack {
            Text("История переводов")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            if !store.entries.isEmpty {
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Очистить всё", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Button("Закрыть") {
                onClose?()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("История пуста")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Здесь будут сохраняться выполненные переводы")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Поиск по тексту…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                ForEach(filteredEntries) { entry in
                    HistoryRow(entry: entry) {
                        store.delete(entry)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct HistoryRow: View {
    let entry: TranslationHistoryEntry
    let onDelete: () -> Void

    @State private var copied = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(LanguageData.displayName(for: entry.sourceLanguage)) → \(LanguageData.displayName(for: entry.targetLanguage))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)

                Spacer()

                Text(Self.dateFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    copyToClipboard(entry.translatedText)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .foregroundColor(copied ? .green : .blue)
                }
                .buttonStyle(.plain)
                .help("Скопировать перевод")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Удалить запись")
            }

            Text(entry.sourceText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)

            Text(entry.translatedText)
                .font(.body)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
