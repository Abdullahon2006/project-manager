import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FieldEditModalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync = SyncService.shared

    var folderToEdit: FolderBento? = nil
    var onSaved: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var selectedIcon: String = "⚡"
    @State private var selectedColor: String = "#3B82F6"
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    let iconPresets = ["⚡", "🎨", "🌱", "🔬", "💼", "🚀", "📚", "🛠️", "🎯", "✨", "💡", "📱", "🌐", "📊", "🔒"]
    let colorPresets = [
        ("#3B82F6", "Blue"),
        ("#8B5CF6", "Purple"),
        ("#10B981", "Emerald"),
        ("#F59E0B", "Amber"),
        ("#EF4444", "Rose"),
        ("#06B6D4", "Cyan"),
        ("#6366F1", "Indigo"),
        ("#64748B", "Slate")
    ]

    var isEditMode: Bool { folderToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Field Identity") {
                    TextField("Field Name (e.g. Operations, Mobile, Health)", text: $name)
                        .font(.body)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(iconPresets, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }) {
                                Text(icon)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(selectedIcon == icon ? Color.blue.opacity(0.18) : Color(.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Accent Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(colorPresets, id: \.0) { hex, label in
                            Button(action: {
                                selectedColor = hex
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }) {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary.opacity(0.4), lineWidth: selectedColor == hex ? 3 : 0)
                                        )
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if isEditMode {
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            HStack {
                                Spacer()
                                Label("Delete Field", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Field" : "New Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "Save" : "Create") {
                        saveField()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let folder = folderToEdit {
                    name = folder.name
                    selectedIcon = folder.icon
                    selectedColor = folder.color
                }
            }
            .confirmationDialog("Delete Field?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Field & Projects", role: .destructive) {
                    deleteField()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Deleting '\(name)' will remove all projects inside it.")
            }
        }
    }

    private func saveField() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        Task {
            do {
                if let existing = folderToEdit {
                    try await sync.updateFolder(
                        id: existing.id,
                        name: trimmed,
                        icon: selectedIcon,
                        color: selectedColor
                    )
                } else {
                    _ = try await sync.createFolder(
                        name: trimmed,
                        icon: selectedIcon,
                        color: selectedColor
                    )
                }
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    onSaved?()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    onSaved?()
                }
            }
        }
    }

    private func deleteField() {
        guard let existing = folderToEdit else { return }
        Task {
            try? await sync.deleteFolder(id: existing.id)
            await MainActor.run {
                dismiss()
                onSaved?()
            }
        }
    }
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 59, 130, 246)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
