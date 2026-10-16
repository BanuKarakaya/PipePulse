import SwiftUI

struct StatusBadge: View {
    let status: PipelineStatus

    private var color: Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .running: .blue
        case .pending: .orange
        case .canceled: .secondary
        }
    }

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Status: \(status.title)")
    }
}
