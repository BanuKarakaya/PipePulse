# PipePulse

Native macOS menu bar MVP for monitoring CI/CD pipelines. The first iteration uses deterministic mock data while keeping provider and security boundaries ready for real integrations.

## Run

Open `Package.swift` in Xcode and run the `PipePulse` scheme. The app appears in the macOS menu bar. The first launch shows onboarding; the dashboard is then available from the PipePulse menu bar item.

From a full Xcode installation, the command-line equivalents are:

```sh
swift build
swift test
```

## Structure

- `Core/Models`: provider-independent repository and pipeline models.
- `Core/Networking`: `PipelineProvider` abstraction and URLSession transport boundary.
- `Core/Security`: Keychain token storage for future provider credentials.
- `Providers/Mock`: deterministic mock data used by the MVP.
- `Features`: dashboard, pipeline details, settings, and onboarding screens.
- `Components`: reusable status, summary, project, and empty-state views.

## GitHub Actions setup

Open Settings, enable GitHub Actions or GitLab CI/CD, enter the corresponding read-only API token, and add repositories as `owner/name` (one per line). Press Done to validate and save; tokens are stored in macOS Keychain. Both integrations can be enabled together. If all integrations are disabled, their fields stay hidden and the app uses mock data.

## Next steps

1. Add GitHub Actions and GitLab clients conforming to `PipelineProvider`.
2. Add Keychain-backed integration forms and OAuth/token validation.
3. Persist selected repositories and connect the refresh interval to a background refresh task.
4. Add richer notification preferences and a notification service protocol implementation for integration tests.
