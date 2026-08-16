import SwiftUI
import FileConverterKit

/// Preset management — the macOS equivalent of the Windows Settings window's
/// preset tree (grouped by the "/"-delimited `fullName` folders, e.g.
/// "Scale 75%/To Mkv"), plus a "Configure presets…" landing surface for when
/// the app is opened directly rather than via a Quick Action hand-off.
struct PresetListView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var selectedPresetID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPresetID) {
                ForEach(groupedPresets, id: \.folder) { group in
                    Section(group.folder) {
                        ForEach(group.presets) { preset in
                            Label(preset.shortName, systemImage: icon(for: preset.outputType))
                                .tag(preset.id)
                        }
                    }
                }
            }
            .navigationTitle("Presets")
            .toolbar {
                ToolbarItem {
                    Menu {
                        ForEach(OutputType.allCases, id: \.self) { type in
                            Button("To \(type.rawValue.uppercased())") { addPreset(for: type) }
                        }
                    } label: {
                        Label("Add Preset", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let index = selectedPresetIndex {
                PresetEditorView(preset: presetBinding(at: index))
            } else {
                ContentUnavailableView("Select a Preset", systemImage: "slider.horizontal.3")
            }
        }
    }

    private struct Group { let folder: String; let presets: [ConversionPreset] }

    private var groupedPresets: [Group] {
        let dict = Dictionary(grouping: appModel.settings.presets) { preset in
            preset.parentFolderNames.first ?? "General"
        }
        return dict.keys.sorted().map { Group(folder: $0, presets: dict[$0]!.sorted { $0.shortName < $1.shortName }) }
    }

    private var selectedPresetIndex: Int? {
        guard let id = selectedPresetID else { return nil }
        return appModel.settings.presets.firstIndex { $0.id == id }
    }

    private func presetBinding(at index: Int) -> Binding<ConversionPreset> {
        Binding(
            get: { appModel.settings.presets[index] },
            set: { appModel.settings.presets[index] = $0; appModel.save() }
        )
    }

    private func addPreset(for type: OutputType) {
        let preset = DefaultPresets.preset(for: type)
        appModel.settings.presets.append(preset)
        appModel.save()
        selectedPresetID = preset.id
    }

    private func icon(for outputType: OutputType) -> String {
        switch outputType.backend {
        case .ffmpeg: return "waveform"
        case .imageMagick: return "photo"
        case .ico: return "app.badge"
        }
    }
}
