import Foundation

extension GitLabCIProvider: PipelineDiagnosticsProviding {
    private var diagnostics: DiagnosticsClient { DiagnosticsClient(session: session, token: accessToken, provider: provider) }

    private func diagnosticsURL(repository: Repository, suffix: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard let project = repository.fullName.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "\(baseURL.absoluteString)/api/v4/projects/\(project)/\(suffix)") else {
            throw PipelineProviderError.invalidResponse
        }
        return url
    }

    func failedJobs(repository: Repository, pipeline: Pipeline) async throws -> FailedJobs {
        guard let runID = pipeline.remoteSequence else {
            throw DiagnosticsError.message("Details are unavailable for this run. Open it in GitLab.")
        }
        var jobs: [FailedJob] = []
        for page in 1...5 {
            let url = try diagnosticsURL(repository: repository, suffix: "pipelines/\(runID)/jobs?scope%5B%5D=failed&include_retried=false&per_page=100&page=\(page)")
            let (data, http, _) = try await diagnostics.get(url)
            let response = try JSONDecoder().decode([GitLabFailedJob].self, from: data)
            jobs += response.filter { $0.status == "failed" }.map { job in
                var summary = "Stage: \(job.stage)"
                if let reason = job.failure_reason { summary += " · " + reason.replacingOccurrences(of: "_", with: " ") }
                if job.allow_failure == true { summary += " · Allowed to fail" }
                return FailedJob(id: job.id, name: job.name, summary: summary, webURL: job.web_url)
            }
            let nextPage = http.value(forHTTPHeaderField: "X-Next-Page")
            if response.isEmpty || nextPage == "" || (nextPage == nil && response.count < 100) {
                return FailedJobs(jobs: jobs, isTruncated: false)
            }
        }
        return FailedJobs(jobs: jobs, isTruncated: true)
    }

    func jobLog(repository: Repository, job: FailedJob) async throws -> LogExcerpt {
        let url = try diagnosticsURL(repository: repository, suffix: "jobs/\(job.id)/trace")
        let (data, _, truncated) = try await diagnostics.get(url, log: true)
        guard !data.isEmpty else { throw DiagnosticsError.message("No log is available for this job yet.") }
        return LogExcerpt.extract(data, token: accessToken, downloadTruncated: truncated)
    }
}

private struct GitLabFailedJob: Decodable {
    let id: Int64
    let name: String
    let stage: String
    let status: String
    let web_url: URL
    let failure_reason: String?
    let allow_failure: Bool?
}
