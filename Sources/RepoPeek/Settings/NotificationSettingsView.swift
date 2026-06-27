import RepoPeekCore
import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle(self.t("Merge request notifications"), isOn: self.$session.settings.gitLabPullRequestNotifications.enabled)
                    .onChange(of: self.session.settings.gitLabPullRequestNotifications.enabled) { _, enabled in
                        if enabled {
                            self.appState.resetGitLabMergeRequestNotificationSnapshots()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                        self.appState.persistSettings()
                    }

                if self.session.settings.gitLabPullRequestNotifications.enabled {
                    Toggle(self.t("New merge requests"), isOn: self.$session.settings.gitLabPullRequestNotifications.newPullRequests)
                        .onChange(of: self.session.settings.gitLabPullRequestNotifications.newPullRequests) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle(self.t("Merge request updates"), isOn: self.$session.settings.gitLabPullRequestNotifications.pullRequestUpdates)
                        .onChange(of: self.session.settings.gitLabPullRequestNotifications.pullRequestUpdates) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle(self.t("Review requested"), isOn: self.$session.settings.gitLabPullRequestNotifications.reviewRequests)
                        .onChange(of: self.session.settings.gitLabPullRequestNotifications.reviewRequests) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle(self.t("New comments"), isOn: self.$session.settings.gitLabPullRequestNotifications.comments)
                        .onChange(of: self.session.settings.gitLabPullRequestNotifications.comments) { _, _ in
                            self.appState.persistSettings()
                        }
                    Picker(self.t("When clicked"), selection: self.$session.settings.gitLabPullRequestNotifications.clickAction) {
                        ForEach(GitLabPullRequestNotificationClickAction.allCases, id: \.self) { action in
                            Text(self.t(action.label))
                                .tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: self.session.settings.gitLabPullRequestNotifications.clickAction) { _, _ in
                        self.appState.persistSettings()
                    }
                }
            } header: {
                Text("GitLab")
            } footer: {
                Text(self.t("Scoped to pinned repositories. The first refresh records the current state without sending notifications."))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}
