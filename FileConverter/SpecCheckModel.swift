import Foundation
import AppKit
import UniformTypeIdentifiers
import FileConverterKit

/// One file in the Spec Check list and where it is in the
/// check -> fix -> re-check loop.
struct SpecCheckItem: Identifiable {
    enum CheckState {
        case checking
        case checked(SpecCheckResult)
        case failed(String)
    }

    enum FixState {
        case idle
        /// The planner explained why it can't fix this automatically.
        case unavailable(String)
        case fixing(progress: Double)
        /// The fix ran; `result` is the re-check of the *output* file.
        case fixed(outputURL: URL, result: SpecCheckResult)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var check: CheckState = .checking
    var fix: FixState = .idle

    var result: SpecCheckResult? {
        if case .checked(let result) = check { return result }
        return nil
    }

    var isFixing: Bool {
        if case .fixing = fix { return true }
        return false
    }

    /// Status after any fix: the fixed file's verdict when there is one.
    var effectiveStatus: SpecFindingStatus? {
        if case .fixed(_, let fixedResult) = fix { return fixedResult.status }
        return result?.status
    }
}

/// Drives the Spec Check tab: probes dropped files against the selected
/// spec, runs automatic fixes through `ConversionQueue`, re-checks the
/// outputs, and exports reports.
///
/// Fixes deliberately don't go through `ConversionSessionModel`: that one
/// posts `sessionFinishedNotification`, which can auto-quit the app — fine
/// for a Quick Action hand-off, wrong in the middle of a review session.
@MainActor
final class SpecCheckModel: ObservableObject {
    @Published private(set) var items: [SpecCheckItem] = []
    @Published var fitMode: FrameFitMode = .pad
    @Published var exportError: String?

    private var maxConcurrency = 2

    var isBusy: Bool {
        items.contains { item in
            if case .checking = item.check { return true }
            return item.isFixing
        }
    }

    var counts: (pass: Int, review: Int, fail: Int) {
        var pass = 0, review = 0, fail = 0
        for item in items {
            switch item.effectiveStatus {
            case .pass?: pass += 1
            case .warning?: review += 1
            case .fail?: fail += 1
            case nil: break
            }
        }
        return (pass, review, fail)
    }

    /// Items whose original fails and that haven't been fixed yet.
    var fixableItems: [SpecCheckItem] {
        items.filter { item in
            guard item.result?.status == .fail, !item.isFixing else { return false }
            if case .fixed = item.fix { return false }
            return true
        }
    }

    func configure(maxConcurrency: Int) {
        self.maxConcurrency = max(1, maxConcurrency)
    }

    // MARK: - Checking

    func add(_ urls: [URL], spec: DeliverySpec) {
        let existing = Set(items.map { $0.url.standardizedFileURL })
        let newURLs = urls
            .map(\.standardizedFileURL)
            .filter { !existing.contains($0) && !$0.hasDirectoryPath }
        guard !newURLs.isEmpty else { return }
        let newItems = newURLs.map { SpecCheckItem(url: $0) }
        items.append(contentsOf: newItems)
        for item in newItems {
            runCheck(itemID: item.id, spec: spec)
        }
    }

    /// Re-runs every check (e.g. after switching spec). Clears fixes, since
    /// they were planned for the previous spec.
    func recheckAll(spec: DeliverySpec) {
        for index in items.indices where !items[index].isFixing {
            items[index].check = .checking
            items[index].fix = .idle
            runCheck(itemID: items[index].id, spec: spec)
        }
    }

    func remove(_ itemID: SpecCheckItem.ID) {
        items.removeAll { $0.id == itemID && !$0.isFixing }
    }

    func clear() {
        items.removeAll { !$0.isFixing }
    }

    private func runCheck(itemID: SpecCheckItem.ID, spec: DeliverySpec) {
        guard let url = items.first(where: { $0.id == itemID })?.url else { return }
        Task {
            let state: SpecCheckItem.CheckState
            do {
                state = .checked(try await SpecCheckService.check(url, against: spec))
            } catch {
                state = .failed(error.localizedDescription)
            }
            update(itemID) { $0.check = state }
        }
    }

    // MARK: - Fixing

    /// What the fix would do, for the confirmation UI, or why it can't.
    func plan(for item: SpecCheckItem, spec: DeliverySpec) -> Result<SpecFixPlan, SpecFixUnavailableReason>? {
        guard let result = item.result else { return nil }
        return SpecFixPlanner.plan(for: result, spec: spec, options: SpecFixOptions(fitMode: fitMode))
    }

    func fix(_ itemID: SpecCheckItem.ID, spec: DeliverySpec) {
        guard let item = items.first(where: { $0.id == itemID }), let planResult = plan(for: item, spec: spec) else { return }
        switch planResult {
        case .failure(let reason):
            update(itemID) { $0.fix = .unavailable(reason.localizedDescription) }
        case .success(let plan):
            run(plan, itemID: itemID, inputURL: item.url, spec: spec)
        }
    }

    func fixAll(spec: DeliverySpec) {
        for item in fixableItems {
            fix(item.id, spec: spec)
        }
    }

    private func run(_ plan: SpecFixPlan, itemID: SpecCheckItem.ID, inputURL: URL, spec: DeliverySpec) {
        update(itemID) { $0.fix = .fixing(progress: 0) }
        let queue = ConversionQueue(maxConcurrency: 1)
        Task {
            let jobID = await queue.enqueue(inputURL: inputURL, preset: plan.preset)
            async let completion: Void = queue.runAll()

            // Same poll pattern as ConversionSessionModel — the queue has
            // no push notifications.
            while true {
                guard let status = await queue.status(for: jobID) else { break }
                if status.state == .done || status.state == .failed { break }
                update(itemID) { $0.fix = .fixing(progress: status.progress) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            _ = await completion

            guard let status = await queue.status(for: jobID) else { return }
            if status.state == .done, let output = status.outputURLs.first {
                do {
                    let recheck = try await SpecCheckService.check(output, against: spec)
                    update(itemID) { $0.fix = .fixed(outputURL: output, result: recheck) }
                } catch {
                    update(itemID) { $0.fix = .failed("Fixed file couldn't be re-checked: \(error.localizedDescription)") }
                }
            } else {
                update(itemID) { $0.fix = .failed(status.errorDescription ?? "Conversion failed.") }
            }
        }
    }

    private func update(_ itemID: SpecCheckItem.ID, _ change: (inout SpecCheckItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        change(&items[index])
    }

    // MARK: - Export

    /// Results for the report: the fixed file's check when a fix succeeded
    /// (that's what will be delivered), otherwise the original's.
    var reportResults: [SpecCheckResult] {
        items.compactMap { item in
            if case .fixed(_, let fixedResult) = item.fix { return fixedResult }
            return item.result
        }
    }

    enum ReportFormat {
        case csv, html

        var contentType: UTType { self == .csv ? .commaSeparatedText : .html }
        var fileExtension: String { self == .csv ? "csv" : "html" }
    }

    func export(_ format: ReportFormat) {
        let results = reportResults
        guard !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "Spec Check report.\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = format == .csv ? SpecCheckReport.csv(results) : SpecCheckReport.html(results)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportError = error.localizedDescription
        }
    }
}
