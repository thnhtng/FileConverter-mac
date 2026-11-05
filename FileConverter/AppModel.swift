import Foundation
import SwiftUI
import FileConverterKit

/// What the main window is currently showing. Unlike the Windows shell
/// extension — which builds an arbitrary, fully dynamic submenu of every
/// compatible preset directly in Explorer's context menu (`CreateMenu`,
/// FileConverterExtension.cs:93-187) — a macOS Quick Action / Action
/// Extension is ONE static menu entry with ONE fixed title (`NSExtension`
/// Info.plist), because the OS discovers/registers `.appex` bundles ahead
/// of time; it can't render a runtime-defined tree of user-editable
/// presets the way a COM shell extension can. So the Quick Action here
/// always just hands off the file selection, and — when the hand-off
/// didn't/couldn't name an exact preset — the app itself shows a preset
/// picker before converting. This is a platform constraint, not a
/// downgrade: it's the only way to support arbitrary/user-created presets
/// (a fixed set of `.appex` targets, one per preset, couldn't do that
/// either).
enum LaunchState {
    case idle
    case choosingPreset(files: [URL])
    case converting(ConversionSessionModel)
}

/// Root app state: loaded settings/presets, and the current launch state.
/// Replaces the Windows app's `SettingsService` + `MainViewModel` combo,
/// minus the WPF data-binding machinery.
/// Top-level tabs of the main window.
enum MainTab: String, CaseIterable, Identifiable {
    case specCheck = "Spec Check"
    case presets = "Presets"
    case settings = "Settings"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var launchState: LaunchState = .idle
    @Published var loadError: String?
    @Published var selectedTab: MainTab = .specCheck
    @Published var selectedSpecID: UUID?

    /// Spec Check tab state. Owned here so Quick Action / CLI hand-offs
    /// (`LaunchRequest.Mode.check`) can feed it files.
    let specCheck = SpecCheckModel()

    private let storeURL: URL

    init(storeURL: URL = SettingsStore.defaultStoreURL) {
        self.storeURL = storeURL
        do {
            self.settings = try SettingsStore.loadOrSeed(url: storeURL)
        } catch {
            self.settings = AppSettings()
            self.loadError = error.localizedDescription
        }
        if settings.deliverySpecs.isEmpty {
            settings.deliverySpecs = DefaultSpecs.all
        }
        selectedSpecID = settings.deliverySpecs.first?.id
        specCheck.configure(maxConcurrency: settings.maximumSimultaneousConversions)
    }

    /// The spec Spec Check currently checks against.
    var selectedSpec: DeliverySpec? {
        settings.deliverySpecs.first { $0.id == selectedSpecID } ?? settings.deliverySpecs.first
    }

    /// Opens files in Spec Check against the selected spec.
    func checkFiles(_ files: [URL]) {
        guard let spec = selectedSpec else {
            loadError = "Add a delivery spec first."
            return
        }
        launchState = .idle
        selectedTab = .specCheck
        specCheck.add(files, spec: spec)
    }

    func save() {
        do {
            try SettingsStore.save(settings, to: storeURL)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Presets compatible with every one of the given files' extensions —
    /// what the preset picker offers, and what an exact-name match is
    /// validated against.
    func compatiblePresets(forFiles files: [URL]) -> [ConversionPreset] {
        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        return settings.presets.filter { preset in
            extensions.allSatisfy(preset.accepts(inputExtension:))
        }
    }

    /// Entry point for both hand-off paths (Quick Action URL scheme + CLI
    /// launch, see LaunchRequest). Starts converting immediately if the
    /// request already names a valid, compatible preset; otherwise shows
    /// the picker.
    func handle(request: LaunchRequest) {
        guard !request.fileURLs.isEmpty else { return }

        if request.mode == .check {
            checkFiles(request.fileURLs)
            return
        }

        if let name = request.presetName,
           let preset = settings.presets.first(where: { $0.fullName == name || $0.shortName == name }),
           compatiblePresets(forFiles: request.fileURLs).contains(where: { $0.id == preset.id }) {
            begin(files: request.fileURLs, preset: preset)
            return
        }

        let candidates = compatiblePresets(forFiles: request.fileURLs)
        if candidates.count == 1 {
            begin(files: request.fileURLs, preset: candidates[0])
        } else if candidates.isEmpty {
            loadError = "No preset accepts this file type."
        } else {
            launchState = .choosingPreset(files: request.fileURLs)
        }
    }

    func begin(files: [URL], preset: ConversionPreset) {
        let session = ConversionSessionModel(
            inputURLs: files,
            preset: preset,
            maxConcurrency: settings.maximumSimultaneousConversions
        )
        launchState = .converting(session)
        session.start()
    }
}
