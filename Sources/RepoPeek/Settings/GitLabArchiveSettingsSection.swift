import AppKit
import RepoPeekCore
import SwiftUI

struct GitLabArchiveSettingsSection: View {
    @Binding var settings: GitLabArchiveSettings
    let language: AppLanguage
    let persist: () -> Void
    @State private var repository = ""
    @State private var statuses: [String: GitLabArchiveSourceStatus] = [:]
    @State private var updatingIDs = Set<String>()
    @State private var updateError: String?

    var body: some View {
        Section {
            Toggle(self.t("Use archives when rate limited"), isOn: self.fallbackBinding)

            if self.settings.sources.isEmpty {
                Text(self.t("No GitLab archives configured."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(self.settings.sources) { source in
                    self.row(for: source)
                }
            }

            if let updateError {
                Text(updateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LabeledContent(self.t("Repo")) {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("", text: self.$repository, prompt: Text(self.t("owner/repo, URL, or local path")))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, maxWidth: .infinity)
                        .layoutPriority(1)

                    HStack(spacing: 8) {
                        Button(self.t("Add Repo")) {
                            self.addArchive()
                        }
                        .disabled(!self.canAdd)
                        .fixedSize()

                        Button(self.t("Choose Repo…")) {
                            self.chooseDirectory { self.repository = $0 }
                        }
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text(self.t("GitLab Archives"))
        } footer: {
            Text(self.t("Point RepoPeek at a snapshot repository. RepoPeek manages the imported database internally and uses it only when GitLab is rate limited."))
        }
        .onAppear {
            self.refreshStatuses()
        }
        .onChange(of: self.settings.sources) {
            self.refreshStatuses()
        }
    }

    private var fallbackBinding: Binding<Bool> {
        Binding(
            get: { self.settings.preferArchiveWhenRateLimited },
            set: { newValue in
                self.settings.preferArchiveWhenRateLimited = newValue
                self.persist()
            }
        )
    }

    private var canAdd: Bool {
        guard let source = GitLabArchiveStore.source(repository: self.repository) else {
            return false
        }

        return self.settings.sources.contains { self.matches($0, source) } == false
    }

    private func row(for source: GitLabArchiveSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(source.name, isOn: self.enabledBinding(for: source.id))
                Spacer()
                Button {
                    self.updateArchive(source)
                } label: {
                    if self.updatingIDs.contains(source.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(self.updatingIDs.contains(source.id))
                .help(self.t("Pull and import archive"))
                Button {
                    self.settings.sources.removeAll { $0.id == source.id }
                    self.persist()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(self.t("Remove archive"))
            }

            Text(self.detailLine(for: source))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let status = self.statuses[source.id] {
                Text(self.statusLine(for: status))
                    .font(.caption2)
                    .foregroundStyle(status.readyForRead ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                self.settings.sources.first(where: { $0.id == id })?.enabled ?? false
            },
            set: { newValue in
                guard let index = self.settings.sources.firstIndex(where: { $0.id == id }) else { return }

                self.settings.sources[index].enabled = newValue
                self.persist()
            }
        )
    }

    private func detailLine(for source: GitLabArchiveSource) -> String {
        let repo = source.remoteURL ?? source.localRepositoryPath.map(PathFormatter.displayString) ?? "-"
        return self.format("repo: %@", repo)
    }

    private func statusLine(for status: GitLabArchiveSourceStatus) -> String {
        var parts = [self.t(status.readyForRead ? "ready" : "not ready")]
        if let rows = status.importedRowCount {
            parts.append(self.format("%d rows", rows))
        }
        if let lastImportAt = status.lastImportAt {
            parts.append(self.format("imported %@", RelativeFormatter.string(from: lastImportAt, relativeTo: Date())))
        }
        if status.issues.isEmpty == false {
            parts.append(status.issues.joined(separator: "; "))
        }
        return parts.joined(separator: " · ")
    }

    private func addArchive() {
        guard let source = GitLabArchiveStore.source(repository: self.repository),
              self.settings.sources.contains(where: { self.matches($0, source) }) == false
        else { return }

        self.settings.sources.append(source)
        self.repository = ""
        self.persist()
        self.refreshStatuses()
    }

    private func updateArchive(_ source: GitLabArchiveSource) {
        self.updateError = nil
        self.updatingIDs.insert(source.id)
        Task.detached {
            do {
                let update = try GitLabArchiveStore.update(source: source)
                await MainActor.run {
                    if let index = self.settings.sources.firstIndex(where: { $0.id == source.id }) {
                        self.settings.sources[index] = update.source
                        self.persist()
                    }
                    self.updatingIDs.remove(source.id)
                    self.refreshStatuses()
                }
            } catch {
                await MainActor.run {
                    self.updateError = error.localizedDescription
                    self.updatingIDs.remove(source.id)
                    self.refreshStatuses()
                }
            }
        }
    }

    private func refreshStatuses() {
        let values = (try? GitLabArchiveStore.statuses(settings: self.settings)) ?? []
        self.statuses = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func chooseDirectory(_ apply: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            apply(PathFormatter.abbreviateHome(url.resolvingSymlinksInPath().path))
        }
    }

    private func matches(_ existing: GitLabArchiveSource, _ candidate: GitLabArchiveSource) -> Bool {
        GitLabArchiveStore.sameArchiveLocation(existing, candidate)
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, language: self.language, arguments)
    }
}
