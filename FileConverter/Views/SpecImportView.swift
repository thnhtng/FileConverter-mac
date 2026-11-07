import SwiftUI
import FileConverterKit

/// Paste a partner's spec (email, help-center page, PDF excerpt) and let
/// Claude draft a `DeliverySpec`. The draft opens in the editor flagged for
/// review — the AI proposes, a person confirms.
struct SpecImportView: View {
    var onDraft: (DeliverySpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var apiKey = KeychainStore.read(KeychainStore.claudeAPIKeyAccount) ?? ""
    @State private var hasStoredKey = KeychainStore.read(KeychainStore.claudeAPIKeyAccount) != nil
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Draft a spec from text", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("Paste the requirements you were sent. Claude turns them into a checklist; you review it before it's used. Only the text you paste is sent — never your files.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 200)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("e.g. \"Video: MP4 or MOV, H.264, 9:16, 1080×1920, 5–60 seconds, max 30 MB, sound on.\"")
                            .foregroundStyle(.tertiary)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .border(Color.secondary.opacity(0.3))

            if !hasStoredKey {
                HStack {
                    SecureField("Claude API key", text: $apiKey)
                    Text("Saved in your Keychain").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await draft() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Draft Spec")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func draft() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if !hasStoredKey {
            KeychainStore.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: KeychainStore.claudeAPIKeyAccount)
        }
        do {
            let spec = try await ClaudeSpecImporter(apiKey: apiKey).importSpec(from: text)
            hasStoredKey = true
            onDraft(spec)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
