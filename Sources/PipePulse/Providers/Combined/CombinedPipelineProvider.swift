import Foundation

struct CombinedPipelineProvider: PipelineProvider {
    let providers: [any PipelineProvider]

    var provider: CIProvider { providers.first?.provider ?? .githubActions }
    var sourceTitle: String { providers.map(\.sourceTitle).joined(separator: " + ") }

    func fetchProjects() async throws -> [Project] {
        try await withThrowingTaskGroup(of: [Project].self, returning: [Project].self) { group in
            for provider in providers {
                group.addTask {
                    try await provider.fetchProjects()
                }
            }

            var projects: [Project] = []
            for try await providerProjects in group {
                projects.append(contentsOf: providerProjects)
            }
            return projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
