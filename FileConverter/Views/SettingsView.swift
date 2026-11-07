import SwiftUI
import FileConverterKit

/// Global settings — the macOS equivalent of the subset of Settings.cs that
/// isn't per-preset (auto-upgrade/telemetry intentionally out of scope, per
/// the plan).
struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var apiKey = KeychainStore.read(KeychainStore.claudeAPIKeyAccount) ?? ""
    @State private var apiKeySaved = false

    var body: some View {
        Form {
            Stepper(
                "Simultaneous conversions: \(appModel.settings.maximumSimultaneousConversions)",
                value: $appModel.settings.maximumSimultaneousConversions,
                in: 1...16
            )
            Toggle("Quit automatically when conversions finish", isOn: $appModel.settings.exitApplicationWhenConversionsFinished)

            Section {
                SecureField("Claude API key", text: $apiKey)
                HStack {
                    Button("Save Key") {
                        apiKeySaved = KeychainStore.write(
                            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            account: KeychainStore.claudeAPIKeyAccount
                        )
                    }
                    if apiKeySaved {
                        Label("Saved", systemImage: "checkmark").foregroundStyle(.green)
                    }
                }
            } header: {
                Text("AI spec import")
            } footer: {
                Text("Optional. Used only for \"Draft from Text with AI\" in Spec Check — the pasted spec text is sent to the Claude API, never your files. Stored in your Keychain.")
                    .foregroundStyle(.secondary)
            }

            Section("Backends") {
                LabeledContent("ffmpeg", value: BinaryLocator.locate(.ffmpeg)?.path ?? "Not found")
                LabeledContent("ImageMagick", value: BinaryLocator.locate(.magick)?.path ?? "Not found")
                LabeledContent("LibreOffice") {
                    if BinaryLocator.isLibreOfficeAvailable {
                        Text(BinaryLocator.locate(.soffice)?.path ?? "")
                    } else {
                        Text("Not installed — Office-document presets are disabled")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .onChange(of: appModel.settings.maximumSimultaneousConversions) { _, newValue in
            appModel.save()
            appModel.specCheck.configure(maxConcurrency: newValue)
        }
        .onChange(of: apiKey) { _, _ in apiKeySaved = false }
        .onChange(of: appModel.settings.exitApplicationWhenConversionsFinished) { _, _ in appModel.save() }
    }
}
