import Foundation

/// Exports Spec Check results so they can be sent to whoever made the
/// files: CSV for spreadsheets, a self-contained HTML page for Slack/email.
public enum SpecCheckReport {
    public static func csv(_ results: [SpecCheckResult]) -> String {
        var rows = [["File", "Spec", "Overall", "Rule", "Status", "Expected", "Actual"]]
        for result in results {
            if result.findings.isEmpty {
                rows.append([result.info.fileURL.lastPathComponent, result.specName, label(result.status), "", "", "", ""])
            }
            for finding in result.findings {
                rows.append([
                    result.info.fileURL.lastPathComponent, result.specName, label(result.status),
                    finding.rule.title, label(finding.status), finding.expected, finding.actual
                ])
            }
        }
        return rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func html(_ results: [SpecCheckResult], generatedAt date: Date = Date()) -> String {
        let passed = results.filter { $0.status == .pass }.count
        let warned = results.filter { $0.status == .warning }.count
        let failed = results.filter { $0.status == .fail }.count

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var body = ""
        for result in results {
            body += "<section class=\"file \(result.status.rawValue)\">"
            body += "<h2>\(icon(result.status)) \(escape(result.info.fileURL.lastPathComponent))</h2>"
            body += "<p class=\"spec\">\(escape(result.specName))</p>"
            if result.findings.isEmpty {
                body += "<p>No rules apply.</p>"
            } else {
                body += "<table><thead><tr><th>Rule</th><th>Expected</th><th>Actual</th><th></th></tr></thead><tbody>"
                for finding in result.findings {
                    body += "<tr class=\"\(finding.status.rawValue)\"><td>\(escape(finding.rule.title))</td>"
                    body += "<td>\(escape(finding.expected))</td><td>\(escape(finding.actual))</td>"
                    body += "<td>\(icon(finding.status))</td></tr>"
                }
                body += "</tbody></table>"
            }
            body += "</section>\n"
        }

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Spec Check report</title>
        <style>
        :root { color-scheme: light dark; --fg:#1d1d1f; --muted:#6e6e73; --bg:#fff; --line:#e5e5ea; --ok:#1a7f37; --warn:#9a6700; --bad:#cf222e; }
        @media (prefers-color-scheme: dark) { :root { --fg:#f5f5f7; --muted:#a1a1a6; --bg:#1c1c1e; --line:#3a3a3c; --ok:#3fb950; --warn:#d29922; --bad:#f85149; } }
        body { font: 15px/1.5 -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg); max-width: 860px; margin: 32px auto; padding: 0 16px; }
        h1 { font-size: 24px; margin: 0 0 4px; } .muted, .spec { color: var(--muted); margin: 0 0 12px; }
        .summary span { margin-right: 16px; font-weight: 600; }
        section.file { border: 1px solid var(--line); border-radius: 12px; padding: 16px; margin: 16px 0; overflow-x: auto; }
        section.file h2 { font-size: 17px; margin: 0; word-break: break-all; }
        table { border-collapse: collapse; width: 100%; } th, td { text-align: left; padding: 6px 8px; border-top: 1px solid var(--line); }
        th { color: var(--muted); font-weight: 500; font-size: 13px; }
        tr.fail td { color: var(--bad); } tr.warning td { color: var(--warn); }
        .ok { color: var(--ok); } .warn { color: var(--warn); } .bad { color: var(--bad); }
        </style></head><body>
        <h1>Spec Check report</h1>
        <p class="muted">\(escape(formatter.string(from: date))) · \(results.count) file(s)</p>
        <p class="summary"><span class="ok">✓ \(passed) pass</span><span class="warn">! \(warned) to review</span><span class="bad">✕ \(failed) fail</span></p>
        \(body)
        </body></html>
        """
    }

    public static func label(_ status: SpecFindingStatus) -> String {
        switch status {
        case .pass: return "Pass"
        case .warning: return "Review"
        case .fail: return "Fail"
        }
    }

    private static func icon(_ status: SpecFindingStatus) -> String {
        switch status {
        case .pass: return "<span class=\"ok\">✓</span>"
        case .warning: return "<span class=\"warn\">!</span>"
        case .fail: return "<span class=\"bad\">✕</span>"
        }
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
