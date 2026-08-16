import SwiftUI
import FileConverterKit

/// Root view: routes on `AppModel.launchState` — preset picker or
/// conversion progress when a Quick Action hand-off (or CLI launch) is in
/// flight, otherwise the preset/settings management surface. Matches the
/// Windows app's Pages.Main vs. Pages.Help/Settings split
/// (Application.xaml.cs `Initialize`/`RunConversions`).
struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var tab: Tab = .presets

    private enum Tab: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case settings = "Settings"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch appModel.launchState {
            case .converting(let session):
                ConversionProgressView(session: session) {
                    appModel.launchState = .idle
                }
            case .choosingPreset(let files):
                PresetPickerView(files: files)
            case .idle:
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding()

                    switch tab {
                    case .presets: PresetListView()
                    case .settings: SettingsView()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .alert("Error", isPresented: Binding(
            get: { appModel.loadError != nil },
            set: { if !$0 { appModel.loadError = nil } }
        )) {
            Button("OK") { appModel.loadError = nil }
        } message: {
            Text(appModel.loadError ?? "")
        }
    }
}
