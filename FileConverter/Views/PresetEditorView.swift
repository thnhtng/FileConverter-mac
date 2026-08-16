import SwiftUI
import FileConverterKit

/// Per-preset settings editor. Field set mirrors the Windows Settings
/// window's per-output-type panel (Views/SettingsWindow.xaml), reduced to
/// the knobs each `FormatSettings` case actually carries.
struct PresetEditorView: View {
    @Binding var preset: ConversionPreset

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $preset.fullName)
                Picker("Output type", selection: outputTypeBinding) {
                    ForEach(OutputType.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Picker("After conversion", selection: $preset.inputPostConversionAction) {
                    Text("Do nothing").tag(InputPostConversionAction.none)
                    Text("Move original to Converted/").tag(InputPostConversionAction.moveInArchiveFolder)
                    Text("Delete original").tag(InputPostConversionAction.delete)
                }
                TextField("Output filename template", text: $preset.outputFileNameTemplate)
                LabeledContent("Accepted input types", value: preset.inputTypes.joined(separator: ", "))
            }

            switch preset.settings {
            case .audio(let s):
                AudioSettingsSection(settings: Binding(get: { s }, set: { preset.settings = .audio($0) }))
            case .video(let s):
                VideoSettingsSection(settings: Binding(get: { s }, set: { preset.settings = .video($0) }))
            case .gif(let s):
                GifSettingsSection(settings: Binding(get: { s }, set: { preset.settings = .gif($0) }))
            case .image(let s):
                ImageSettingsSection(settings: Binding(get: { s }, set: { preset.settings = .image($0) }))
            case .document(let s):
                DocumentSettingsSection(settings: Binding(get: { s }, set: { preset.settings = .document($0) }))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(preset.shortName)
    }

    /// Changing output type re-seeds default settings for the new family,
    /// matching ConversionPreset.cs's OutputType setter (line 123-135).
    private var outputTypeBinding: Binding<OutputType> {
        Binding(
            get: { preset.outputType },
            set: { newType in
                preset.outputType = newType
                preset.settings = DefaultPresets.defaultSettings(for: newType)
                preset.inputTypes = InputCategoryClassifier.compatibleInputExtensions(for: newType)
            }
        )
    }
}

private struct AudioSettingsSection: View {
    @Binding var settings: AudioSettings
    var body: some View {
        Section("Audio") {
            Stepper("Bitrate: \(settings.bitrateKbps) kbps", value: $settings.bitrateKbps, in: 16...500, step: 16)
            Stepper("Channels: \(settings.channelCount == 0 ? "source" : "\(settings.channelCount)")", value: $settings.channelCount, in: 0...8)
        }
    }
}

private struct VideoSettingsSection: View {
    @Binding var settings: VideoSettings
    var body: some View {
        Section("Video") {
            Stepper("Quality: \(settings.quality)", value: $settings.quality, in: 0...63)
            Picker("Encoding speed", selection: $settings.encodingSpeed) {
                ForEach(VideoEncodingSpeed.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Slider(value: $settings.scale, in: 0.1...2, step: 0.05) {
                Text("Scale")
            }
            Toggle("Include audio", isOn: $settings.enableAudio)
            if settings.enableAudio {
                Stepper("Audio bitrate: \(settings.audioBitrateKbps) kbps", value: $settings.audioBitrateKbps, in: 16...500, step: 16)
            }
        }
    }
}

private struct GifSettingsSection: View {
    @Binding var settings: GifSettings
    var body: some View {
        Section("GIF") {
            Slider(value: $settings.scale, in: 0.1...2, step: 0.05) { Text("Scale") }
            Stepper("Frame rate: \(settings.framesPerSecond) fps", value: $settings.framesPerSecond, in: 1...60)
        }
    }
}

private struct ImageSettingsSection: View {
    @Binding var settings: ImageSettings
    var body: some View {
        Section("Image") {
            Stepper("Quality: \(settings.quality)", value: $settings.quality, in: 1...100)
            Slider(value: $settings.scale, in: 0.1...2, step: 0.05) { Text("Scale") }
            Toggle("Clamp size to power of two", isOn: $settings.clampSizeToPowerOfTwo)
        }
    }
}

private struct DocumentSettingsSection: View {
    @Binding var settings: DocumentSettings
    var body: some View {
        Section("Document") {
            Stepper("Density: \(settings.densityDpi) dpi", value: $settings.densityDpi, in: 72...600, step: 25)
        }
    }
}
