import SwiftUI
import FileConverterKit

/// Manage delivery specs: edit, duplicate, delete, restore the examples,
/// or draft a new one from pasted text with Claude.
struct SpecLibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var showingImport = false
    /// Specs drafted by AI in this session — shown with a "review" banner.
    @State private var aiDraftIDs: Set<UUID> = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(appModel.settings.deliverySpecs) { spec in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(spec.name).lineLimit(1)
                            if aiDraftIDs.contains(spec.id) {
                                Image(systemName: "sparkles").foregroundStyle(.purple).help("AI draft — review before use")
                            }
                        }
                        Text(spec.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(spec.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Button("Blank Spec") { add(DeliverySpec(name: "New spec")) }
                        Button("Duplicate Selected") { duplicateSelected() }
                            .disabled(selectedIndex == nil)
                        Divider()
                        Button("Draft from Text with AI…") { showingImport = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button(role: .destructive) { deleteSelected() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIndex == nil || appModel.settings.deliverySpecs.count <= 1)
                }
            }
        } detail: {
            if let index = selectedIndex {
                SpecEditorView(
                    spec: specBinding(at: index),
                    isAIDraft: aiDraftIDs.contains(appModel.settings.deliverySpecs[index].id),
                    onReviewed: { aiDraftIDs.remove(appModel.settings.deliverySpecs[index].id) }
                )
                .id(appModel.settings.deliverySpecs[index].id)
            } else {
                ContentUnavailableView("Select a spec", systemImage: "list.bullet.rectangle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Restore Example Specs") { restoreExamples() }
                    .help("Re-adds the built-in example specs (your own specs are kept).")
                Spacer()
                Button("Done") {
                    // Re-check with the (possibly edited) selected spec.
                    if let spec = appModel.selectedSpec { appModel.specCheck.recheckAll(spec: spec) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear { selection = appModel.selectedSpec?.id }
        .sheet(isPresented: $showingImport) {
            SpecImportView { draft in
                add(draft)
                aiDraftIDs.insert(draft.id)
            }
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return appModel.settings.deliverySpecs.firstIndex { $0.id == selection }
    }

    private func specBinding(at index: Int) -> Binding<DeliverySpec> {
        Binding(
            get: { appModel.settings.deliverySpecs[index] },
            set: {
                appModel.settings.deliverySpecs[index] = $0
                appModel.save()
            }
        )
    }

    private func add(_ spec: DeliverySpec) {
        appModel.settings.deliverySpecs.append(spec)
        appModel.save()
        selection = spec.id
    }

    private func duplicateSelected() {
        guard let index = selectedIndex else { return }
        var copy = appModel.settings.deliverySpecs[index]
        copy.id = UUID()
        copy.name += " copy"
        copy.isBuiltIn = false
        add(copy)
    }

    private func deleteSelected() {
        guard let index = selectedIndex, appModel.settings.deliverySpecs.count > 1 else { return }
        let removed = appModel.settings.deliverySpecs.remove(at: index)
        if appModel.selectedSpecID == removed.id {
            appModel.selectedSpecID = appModel.settings.deliverySpecs.first?.id
        }
        appModel.save()
        selection = appModel.settings.deliverySpecs[min(index, appModel.settings.deliverySpecs.count - 1)].id
    }

    private func restoreExamples() {
        let existing = Set(appModel.settings.deliverySpecs.map(\.id))
        for spec in DefaultSpecs.all {
            if let index = appModel.settings.deliverySpecs.firstIndex(where: { $0.id == spec.id }) {
                appModel.settings.deliverySpecs[index] = spec
            } else if !existing.contains(spec.id) {
                appModel.settings.deliverySpecs.append(spec)
            }
        }
        appModel.save()
    }
}

/// Form for one spec. Every rule is optional — an empty field means
/// "don't check this".
struct SpecEditorView: View {
    @Binding var spec: DeliverySpec
    var isAIDraft = false
    var onReviewed: () -> Void = {}

    var body: some View {
        Form {
            if isAIDraft {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Drafted by AI from your text").font(.headline)
                            Text("Compare each field with the original spec before using it. Empty fields aren't checked.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Looks Right", action: onReviewed)
                    }
                }
            }

            Section("General") {
                TextField("Name", text: $spec.name)
                TextField("Notes", text: Binding(
                    get: { spec.notes ?? "" },
                    set: { spec.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(1...4)
                LabeledContent("For") {
                    HStack {
                        ForEach([MediaKind.video, .image, .audio, .document], id: \.self) { kind in
                            Toggle(kind.rawValue.capitalized, isOn: kindBinding(kind))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            Section("File") {
                ListField(title: "Allowed formats", placeholder: "Any (e.g. mp4, mov)", values: $spec.allowedExtensions)
                OptionalNumberField(title: "Max file size", unit: "MB", value: $spec.maxFileSizeMB)
            }

            Section("Frame") {
                OptionalNumberField(title: "Exact width", unit: "px", value: intBinding($spec.width))
                OptionalNumberField(title: "Exact height", unit: "px", value: intBinding($spec.height))
                OptionalNumberField(title: "Min width", unit: "px", value: intBinding($spec.minWidth))
                OptionalNumberField(title: "Min height", unit: "px", value: intBinding($spec.minHeight))
                OptionalNumberField(title: "Max width", unit: "px", value: intBinding($spec.maxWidth))
                OptionalNumberField(title: "Max height", unit: "px", value: intBinding($spec.maxHeight))
                ListField(title: "Aspect ratios", placeholder: "Any (e.g. 9:16, 1:1)", values: ratioBinding)
            }

            Section("Timing") {
                OptionalNumberField(title: "Min duration", unit: "s", value: $spec.minDurationSeconds)
                OptionalNumberField(title: "Max duration", unit: "s", value: $spec.maxDurationSeconds)
                OptionalNumberField(title: "Min frame rate", unit: "fps", value: $spec.minFramesPerSecond)
                OptionalNumberField(title: "Max frame rate", unit: "fps", value: $spec.maxFramesPerSecond)
            }

            Section("Codecs & audio") {
                ListField(title: "Video codecs", placeholder: "Any (e.g. h264, hevc)", values: $spec.allowedVideoCodecs)
                ListField(title: "Audio codecs", placeholder: "Any (e.g. aac)", values: $spec.allowedAudioCodecs)
                Picker("Audio track", selection: $spec.audio) {
                    Text("Optional").tag(AudioRequirement.optional)
                    Text("Required").tag(AudioRequirement.required)
                    Text("Must be silent").tag(AudioRequirement.forbidden)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(spec.name)
    }

    private func kindBinding(_ kind: MediaKind) -> Binding<Bool> {
        Binding(
            get: { spec.mediaKinds.contains(kind) },
            set: { isOn in
                if isOn {
                    if !spec.mediaKinds.contains(kind) { spec.mediaKinds.append(kind) }
                } else {
                    spec.mediaKinds.removeAll { $0 == kind }
                }
            }
        )
    }

    private func intBinding(_ binding: Binding<Int?>) -> Binding<Double?> {
        Binding(
            get: { binding.wrappedValue.map { Double($0) } },
            set: { binding.wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }

    private var ratioBinding: Binding<[String]?> {
        Binding(
            get: { spec.aspectRatios?.map(\.description) },
            set: { strings in
                let ratios = (strings ?? []).compactMap(AspectRatio.init(string:))
                spec.aspectRatios = ratios.isEmpty ? nil : ratios
            }
        )
    }
}

/// A text field bound to an optional number: empty = nil ("any").
struct OptionalNumberField: View {
    let title: String
    var unit: String?
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: $text, prompt: Text("Any"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                if let unit {
                    Text(unit).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                }
            }
        }
        .onAppear { text = value.map { SpecFormat.number($0, maxDecimals: 3) } ?? "" }
        .onChange(of: text) { _, newText in
            let trimmed = newText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            let parsed = trimmed.isEmpty ? nil : Double(trimmed)
            if trimmed.isEmpty || parsed != nil, parsed != value {
                value = parsed
            }
        }
    }
}

/// A comma-separated list field bound to an optional string array:
/// empty = nil ("any"). Values are committed on submit / focus loss so
/// typing "9:" doesn't get rejected mid-entry.
struct ListField: View {
    let title: String
    let placeholder: String
    @Binding var values: [String]?
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text, prompt: Text(placeholder))
            .onAppear { text = (values ?? []).joined(separator: ", ") }
            .onSubmit(commit)
            .onChange(of: text) { _, newText in
                // Commit only when the list parses to something different,
                // and only on separators/edits that complete an item.
                if newText.isEmpty || newText.hasSuffix(",") == false { commit() }
            }
    }

    private func commit() {
        let items = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
        let newValue: [String]? = items.isEmpty ? nil : items
        if newValue != values { values = newValue }
    }
}
