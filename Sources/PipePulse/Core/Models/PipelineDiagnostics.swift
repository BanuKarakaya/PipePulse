import Foundation

struct FailedJob: Identifiable, Sendable, Equatable {
    let id: Int64
    let name: String
    let summary: String
    let webURL: URL
}

struct FailedJobs: Sendable {
    let jobs: [FailedJob]
    let isTruncated: Bool
}

struct LogExcerpt: Sendable {
    let text: String
    let matchedError: Bool
    let isTruncated: Bool

    // Bounded, local extraction — not an AI diagnosis. Never persist raw logs.
    static func extract(_ data: Data, token: String, downloadTruncated: Bool = false) -> Self {
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"section_(start|end):[^\r\n]*"#, with: "", options: .regularExpression)
        if !token.isEmpty { text = text.replacingOccurrences(of: token, with: "[REDACTED]") }
        for pattern in [#"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+"#, #"\b(?:glpat-|github_pat_|gh[pousr]_)[A-Za-z0-9_-]+"#] {
            text = text.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        let lines = text.components(separatedBy: .newlines)
        let matches = lines.indices.filter {
            lines[$0].range(of: #"(?i)(\berror\b|\bfatal\b|\bfailed\b|\bfailure\b|exception|timed? out|exit (?:code|status).*[^0\s])"#, options: .regularExpression) != nil
        }
        var indices = Set<Int>()
        // The last errors generally include the final failure; include surrounding context.
        for index in matches.suffix(12) {
            indices.formUnion(max(0, index - 3)...min(lines.count - 1, index + 3))
        }
        if indices.isEmpty { indices.formUnion(max(0, lines.count - 40)..<lines.count) }
        let selected = Array(indices.sorted().suffix(80))
        var previous: Int?
        let excerpt = selected.map { index -> String in
            let gap = previous.map { index > $0 + 1 } ?? false
            previous = index
            return (gap ? "…\n" : "") + "\(index + 1)  " + String(lines[index].prefix(600))
        }.joined(separator: "\n")
        return Self(
            text: String(excerpt.prefix(16_000)), matchedError: !matches.isEmpty,
            isTruncated: downloadTruncated || selected.count < lines.count || excerpt.count > 16_000
                || selected.contains { lines[$0].count > 600 }
        )
    }
}

protocol PipelineDiagnosticsProviding: Sendable {
    func failedJobs(repository: Repository, pipeline: Pipeline) async throws -> FailedJobs
    func jobLog(repository: Repository, job: FailedJob) async throws -> LogExcerpt
}

enum DiagnosticsError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
