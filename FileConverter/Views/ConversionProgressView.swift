import SwiftUI
import FileConverterKit

/// The window shown while converting — the macOS equivalent of MainWindow.xaml,
/// one row per job with a progress bar, shown every time a Quick Action
/// hand-off arrives (see the plan's "transient, launches per conversion" note).
struct ConversionProgressView: View {
    @ObservedObject var session: ConversionSessionModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(session.jobs) { job in
                ConversionJobRow(job: job)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.isRunning {
                    Button("Cancel") { session.cancelAll() }
                } else {
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle("Converting")
    }

    private var summaryText: String {
        let done = session.jobs.filter { $0.state == .done }.count
        let failed = session.jobs.filter { $0.state == .failed }.count
        var parts = ["\(done)/\(session.jobs.count) done"]
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }
}

private struct ConversionJobRow: View {
    let job: ConversionJobStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.inputURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                stateLabel
            }
            if job.state == .inProgress {
                ProgressView(value: job.progress)
            } else if job.state == .failed, let error = job.errorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch job.state {
        case .ready:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .inProgress:
            Text("\(Int(job.progress * 100))%").font(.caption).foregroundStyle(.secondary)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            EmptyView()
        }
    }
}
