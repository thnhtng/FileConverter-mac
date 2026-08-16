import SwiftUI
import FileConverterKit

/// Shown after a Quick Action hand-off that couldn't resolve to exactly one
/// preset (see the platform-constraint note on `LaunchState`) — the user
/// picks which preset to apply to the files Finder handed off.
struct PresetPickerView: View {
    @EnvironmentObject var appModel: AppModel
    let files: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Convert \(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.headline)
                Text(files.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()

            Divider()

            List(appModel.compatiblePresets(forFiles: files)) { preset in
                Button {
                    appModel.begin(files: files, preset: preset)
                } label: {
                    HStack {
                        Text(preset.shortName)
                        Spacer()
                        Text(preset.outputType.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .navigationTitle("Choose a Preset")
    }
}
