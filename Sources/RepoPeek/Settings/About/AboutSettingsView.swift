import AppKit
import RepoPeekCore
import SwiftUI

@MainActor
struct AboutSettingsView: View {
    let language: AppLanguage
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @State private var didSyncUpdater = false
    @State private var didCopyUpdateDiagnostics = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? RepoPeekProductConstants.displayName
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RepoPeekBuildTimestamp") as? String else { return nil }

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "RepoPeekGitCommit") as? String
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = NSApplication.shared.applicationIconImage {
                Button {
                    if let url = URL(string: "https://gitlab.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(16)
                        .scaleEffect(self.iconHover ? 1.06 : 1.0)
                        .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 6)
                        .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text(self.appName)
                    .font(.title3).bold()
                Text(self.format("Version %@", self.versionString))
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    let suffix: String = {
                        if let git = self.gitCommit, !git.isEmpty, git != "unknown" {
                            return " (\(git))"
                        }
                        return ""
                    }()
                    Text(self.format("Built %@", "\(buildTimestamp)\(suffix)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(self.t("Menubar glance at GitLab repos: CI, issues/MRs, releases, and activity."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 6) {
                AboutLinkRow(icon: "chevron.left.slash.chevron.right", title: "GitLab", url: "https://gitlab.com")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)

            if SparkleController.shared.canCheckForUpdates {
                Divider()
                    .padding(.vertical, 6)
                VStack(spacing: 10) {
                    Toggle(self.t("Check for updates automatically"), isOn: self.$autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button(self.t("Check for Updates…")) {
                        SparkleController.shared.checkForUpdates()
                    }
                    Button(self.t("Copy Update Diagnostics")) {
                        self.copyUpdateDiagnostics()
                    }
                    if self.didCopyUpdateDiagnostics {
                        Text(self.t("Update diagnostics copied."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text(self.t("Updates unavailable in this build."))
                        .foregroundStyle(.secondary)
                    Button(self.t("Copy Update Diagnostics")) {
                        self.copyUpdateDiagnostics()
                    }
                    if self.didCopyUpdateDiagnostics {
                        Text(self.t("Update diagnostics copied."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            Text("© 2026 RepoPeek contributors. MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 112)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .onAppear {
            guard !self.didSyncUpdater else { return }

            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = self.autoUpdateEnabled
                SparkleController.shared.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
                SparkleController.shared.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, language: self.language, arguments)
    }

    private func copyUpdateDiagnostics() {
        let diagnostics = UpdateDiagnostics.current(
            canCheckForUpdates: SparkleController.shared.canCheckForUpdates
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics.pasteboardText, forType: .string)
        self.didCopyUpdateDiagnostics = true
    }
}
