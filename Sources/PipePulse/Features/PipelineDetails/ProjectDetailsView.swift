import SwiftUI
import AppKit

struct ProjectDetailsView: View {
    @EnvironmentObject private var appState: AppState
    let project: Project

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    appState.selectedProjectID = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                    Text(project.repository.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(project.repository.url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open repository")
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: project.repository.provider.systemImage)
                            .foregroundStyle(.tint)
                        Text(project.repository.provider.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(project.pipelines.count) runs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Recent runs")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(project.pipelines.sorted { $0.startedAt > $1.startedAt }) { pipeline in
                            PipelineDetailRow(pipeline: pipeline)
                            if pipeline.id != project.pipelines.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
        }
    }
}

private struct PipelineDetailRow: View {
    let pipeline: Pipeline

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pipeline.status.systemImage)
                .foregroundStyle(statusColor)
                .font(.body.weight(.semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(pipeline.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(pipeline.startedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Label(pipeline.branch, systemImage: "arrow.branch")
                    Text("•")
                    Text(pipeline.durationText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.open(pipeline.webURL)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open pipeline")
        }
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        switch pipeline.status {
        case .success: .green
        case .failed: .red
        case .running: .blue
        case .pending: .orange
        case .canceled: .secondary
        }
    }
}
