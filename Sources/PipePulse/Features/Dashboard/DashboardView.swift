import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let project = appState.selectedProject {
            ProjectDetailsView(project: project)
        } else {
            dashboardContent
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.isLoading && appState.projects.isEmpty {
                ProgressView("Loading pipelines…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = appState.errorMessage, appState.projects.isEmpty {
                EmptyStateView(title: "Couldn’t load pipelines", message: errorMessage, systemImage: "exclamationmark.triangle")
            } else if appState.projects.isEmpty {
                EmptyStateView(title: "No projects yet", message: "Connect an integration to start tracking pipelines.", systemImage: "tray")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summary
                        projectList
                    }
                    .padding(16)
                }
            }

            footer
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("PipePulse")
                    .font(.headline)
                Text("Pipeline monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: appState.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh pipelines")
            .disabled(appState.isLoading)
            Button {
                appState.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            SummaryMetricCard(title: "Healthy", value: appState.successCount, color: .green, systemImage: "checkmark.circle.fill")
            SummaryMetricCard(title: "Failed", value: appState.failedCount, color: .red, systemImage: "xmark.circle.fill")
            SummaryMetricCard(title: "Active", value: appState.runningCount, color: .blue, systemImage: "arrow.triangle.2.circlepath.circle.fill")
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(appState.projects) { project in
                    Button {
                        appState.selectedProjectID = project.id
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                    if project.id != appState.projects.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("\(appState.dataSourceTitle) · Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
