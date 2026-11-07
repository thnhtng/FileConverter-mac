import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileConverterKit

/// Spec Check: drop files, pick a delivery spec, see exactly which rules
/// fail (expected vs actual), and fix them automatically — the person only
/// has to look at the red rows.
struct SpecCheckView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject var model: SpecCheckModel
    @State private var showingLibrary = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .dropDestination(for: URL.self) { urls, _ in
            appModel.checkFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .onChange(of: appModel.selectedSpecID) { _, _ in
            if let spec = appModel.selectedSpec { model.recheckAll(spec: spec) }
        }
        .sheet(isPresented: $showingLibrary) {
            SpecLibraryView()
                .environmentObject(appModel)
        }
        .alert("Export failed", isPresented: Binding(
            get: { model.exportError != nil },
            set: { if !$0 { model.exportError = nil } }
        )) {
            Button("OK") { model.exportError = nil }
        } message: {
            Text(model.exportError ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Picker("Check against", selection: specSelection) {
                    ForEach(appModel.settings.deliverySpecs) { spec in
                        Text(spec.name).tag(Optional(spec.id))
                    }
                }
                .frame(maxWidth: 360)

                Button("Manage Specs…") { showingLibrary = true }

                Spacer()

                Picker("Fix by", selection: $model.fitMode) {
                    Text("Adding bars").tag(FrameFitMode.pad)
                    Text("Cropping").tag(FrameFitMode.crop)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("How to fix a wrong size or aspect ratio: add black bars (nothing is cut off) or crop the edges.")
            }
            if let spec = appModel.selectedSpec {
                Text(spec.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let notes = spec.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var specSelection: Binding<UUID?> {
        Binding(
            get: { appModel.selectedSpec?.id },
            set: { appModel.selectedSpecID = $0 }
        )
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text("Drop videos or images here")
                    .font(.title3.weight(.medium))
                Text("Each file is checked against the selected spec. Anything that doesn't match is flagged with what was expected and what the file has.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                Button("Choose Files…", action: chooseFiles)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                    .padding(16)
            )
        } else if let spec = appModel.selectedSpec {
            List {
                ForEach(model.items) { item in
                    SpecCheckRow(item: item, spec: spec, model: model)
                }
            }
            .listStyle(.inset)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
        } else {
            ContentUnavailableView("No delivery spec", systemImage: "list.bullet.rectangle", description: Text("Add one in Manage Specs…"))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            let counts = model.counts
            if !model.items.isEmpty {
                Label("\(counts.pass) pass", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if counts.review > 0 {
                    Label("\(counts.review) to review", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Label("\(counts.fail) fail", systemImage: "xmark.circle.fill").foregroundStyle(counts.fail > 0 ? Color.red : Color.secondary)
            }
            Spacer()
            if !model.items.isEmpty {
                Menu("Export Report") {
                    Button("HTML (for Slack / email)…") { model.export(.html) }
                    Button("CSV (for spreadsheets)…") { model.export(.csv) }
                }
                .fixedSize()
                .disabled(model.reportResults.isEmpty)
                Button("Clear") { model.clear() }
                    .disabled(model.isBusy)
            }
            Button("Add Files…", action: chooseFiles)
            Button {
                if let spec = appModel.selectedSpec { model.fixAll(spec: spec) }
            } label: {
                Text(model.fixableItems.isEmpty ? "Fix All" : "Fix All (\(model.fixableItems.count))")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.fixableItems.isEmpty)
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .font(.callout)
        .padding()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .image, .audio, .pdf, .data]
        if panel.runModal() == .OK {
            appModel.checkFiles(panel.urls)
        }
    }
}

/// One file: verdict, the rules it breaks, the planned fix, and the
/// fixed file's re-check.
private struct SpecCheckRow: View {
    let item: SpecCheckItem
    let spec: DeliverySpec
    @ObservedObject var model: SpecCheckModel
    @State private var showAllRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                statusIcon(item.result?.status, checking: isChecking)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }

            if case .failed(let message) = item.check {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            if let result = item.result, !result.findings.isEmpty {
                findingsGrid(showAllRules ? result.findings : result.findings.filter { $0.status != .pass })
                if result.findings.contains(where: { $0.status == .pass }) {
                    Button(showAllRules ? "Hide passing rules" : "Show all \(result.findings.count) rules") {
                        showAllRules.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            fixSection
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Remove from List") { model.remove(item.id) }
                .disabled(item.isFixing)
        }
    }

    private var isChecking: Bool {
        if case .checking = item.check { return true }
        return false
    }

    private var subtitle: String {
        guard let result = item.result else { return isChecking ? "Checking…" : "" }
        let info = result.info
        var parts: [String] = []
        if let w = info.displayWidth, let h = info.displayHeight { parts.append("\(w)×\(h)") }
        if let d = info.durationSeconds { parts.append(SpecFormat.seconds(d)) }
        if let fps = info.framesPerSecond { parts.append(SpecFormat.fps(fps)) }
        parts.append(SpecFormat.megabytes(info.fileSizeMB))
        switch result.status {
        case .pass: parts.insert("Meets the spec", at: 0)
        case .warning: parts.insert("\(result.warnings.count) to review", at: 0)
        case .fail: parts.insert("\(result.failures.count) problem\(result.failures.count == 1 ? "" : "s")", at: 0)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        if item.result?.status == .fail {
            switch item.fix {
            case .idle, .failed, .unavailable:
                Button("Fix") { model.fix(item.id, spec: spec) }
                    .disabled(planUnavailableReason != nil)
                    .help(planUnavailableReason ?? "Convert a copy that meets the spec. The original is not changed.")
            case .fixing(let progress):
                ProgressView(value: progress)
                    .frame(width: 90)
            case .fixed(let output, _):
                Button("Show Fixed File") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
            }
        }
    }

    private var plan: Result<SpecFixPlan, SpecFixUnavailableReason>? {
        model.plan(for: item, spec: spec)
    }

    private var planUnavailableReason: String? {
        if case .failure(let reason)? = plan { return reason.localizedDescription }
        return nil
    }

    @ViewBuilder
    private var fixSection: some View {
        switch item.fix {
        case .idle:
            if item.result?.status == .fail {
                switch plan {
                case .success(let fix)?:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fix will:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(fix.actions, id: \.self) { action in
                            Text("• \(action)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .failure(let reason)?:
                    Label(reason.localizedDescription, systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
        case .unavailable(let message), .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .fixing:
            Text("Converting a fixed copy…").font(.caption).foregroundStyle(.secondary)
        case .fixed(let output, let result):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    statusIcon(result.status, checking: false)
                    Text("\(output.lastPathComponent): \(fixedVerdict(result))")
                        .font(.caption.weight(.medium))
                }
                if result.status != .pass {
                    findingsGrid(result.findings.filter { $0.status != .pass })
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func fixedVerdict(_ result: SpecCheckResult) -> String {
        switch result.status {
        case .pass: return "fixed copy meets the spec"
        case .warning: return "fixed copy needs a quick review"
        case .fail: return "still fails \(result.failures.count) rule\(result.failures.count == 1 ? "" : "s")"
        }
    }

    private func findingsGrid(_ findings: [SpecFinding]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
            ForEach(findings) { finding in
                GridRow {
                    statusIcon(finding.status, checking: false).font(.caption)
                    Text(finding.rule.title).font(.caption.weight(.medium))
                    Text("expected \(finding.expected)").font(.caption).foregroundStyle(.secondary)
                    Text("has \(finding.actual)").font(.caption)
                        .foregroundStyle(color(finding.status))
                }
            }
        }
        .padding(.leading, 30)
    }

    @ViewBuilder
    private func statusIcon(_ status: SpecFindingStatus?, checking: Bool) -> some View {
        if checking {
            ProgressView().controlSize(.small)
        } else {
            switch status {
            case .pass?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning?: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .fail?: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case nil: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ status: SpecFindingStatus) -> Color {
        switch status {
        case .pass: return .primary
        case .warning: return .orange
        case .fail: return .red
        }
    }
}
