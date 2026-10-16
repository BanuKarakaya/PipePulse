import SwiftUI

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.repository.provider.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 5) {
                    Text(project.repository.provider.title)
                    Text("•")
                    Text(project.latestPipeline?.branch ?? "No runs")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            if let latest = project.latestPipeline {
                StatusBadge(status: latest.status)
                    .labelStyle(.iconOnly)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.latestPipeline?.status.title ?? "No pipeline")")
    }
}
