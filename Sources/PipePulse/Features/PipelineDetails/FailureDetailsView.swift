import SwiftUI

struct FailureDetailsView: View {
    let repository: Repository
    let pipeline: Pipeline
    let provider: (any PipelineDiagnosticsProviding)?
    let onBack: () -> Void
    @StateObject private var model = FailureDetailsModel()
    @State private var jobsAttempt = 0
    @State private var logAttempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Back to recent runs")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Failure details").font(.headline)
                    Text(pipeline.name).font(.caption).lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: pipeline.webURL) { Image(systemName: "arrow.up.right.square") }
                    .help("Open pipeline in \(repository.provider.title)")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(pipeline.branch, systemImage: "arrow.branch")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Failed jobs").font(.headline)
                    if model.jobsLoading {
                        ProgressView("Loading jobs…").controlSize(.small)
                    } else if let error = model.jobsError {
                        errorMessage(error) { jobsAttempt += 1 }
                    } else if model.jobs.isEmpty {
                        Text("No failed jobs were returned. The run may have been retried, or failed before a job started. Open the pipeline for configuration errors and downstream failures.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Check again") { jobsAttempt += 1 }
                    } else {
                        ForEach(model.jobs) { job in
                            Button { model.selectedJobID = job.id } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(job.name).font(.subheadline.weight(.semibold))
                                        Text(job.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.selectedJobID == job.id { Image(systemName: "chevron.down").font(.caption) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(model.selectedJobID == job.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Inspect failed job \(job.name)")
                        }
                        if model.jobsTruncated {
                            Text("Only the first 500 jobs were checked. Open the pipeline for the complete list.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let job = model.selectedJob {
                        Divider()
                        HStack {
                            Text("Log excerpt").font(.headline)
                            Spacer()
                            Link("Open full log ↗", destination: job.webURL).font(.caption)
                        }
                        if model.logLoading {
                            ProgressView("Loading log…").controlSize(.small)
                        } else if let error = model.logError {
                            errorMessage(error) { logAttempt += 1 }
                        } else if let log = model.log {
                            Text(log.matchedError ? "Error-related lines with surrounding context. This is a log excerpt, not a confirmed root cause." : "No clear error marker found. Showing the last available lines.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(log.text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            if log.isTruncated {
                                Text("Excerpt only; downloads are limited to the first 1 MB. Use Open full log if the failure is missing.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Loaded on demand. Logs stay in memory and are not sent to an AI service. Review for secrets before sharing.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .task(id: jobsAttempt) {
            await model.loadJobs(provider: provider, repository: repository, pipeline: pipeline)
        }
        .task(id: "\(model.selectedJobID ?? -1):\(logAttempt)") {
            await model.loadLog(provider: provider, repository: repository)
        }
    }

    private func errorMessage(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
            Button("Retry loading", action: retry)
        }
    }
}
