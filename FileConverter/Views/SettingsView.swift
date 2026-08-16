import SwiftUI
import FileConverterKit

/// Global settings — the macOS equivalent of the subset of Settings.cs that
/// isn't per-preset (auto-upgrade/telemetry intentionally out of scope, per
/// the plan).
struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Form {
            Stepper(
                "Simultaneous conversions: \(appModel.settings.maximumSimultaneousConversions)",
                value: $appModel.settings.maximumSimultaneousConversions,
                in: 1...16
            )
            Toggle("Quit automatically when conversions finish", isOn: $appModel.settings.exitApplicationWhenConversionsFinished)

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
        .onChange(of: appModel.settings.maximumSimultaneousConversions) { _, _ in appModel.save() }
        .onChange(of: appModel.settings.exitApplicationWhenConversionsFinished) { _, _ in appModel.save() }
    }
}
