import Foundation
import RepoPeekCore

extension AppState {
    /// GitLab PAT mode does not use the GitLab contribution heatmap endpoint.
    func loadContributionHeatmapIfNeeded(for username: String) async {
        guard self.session.settings.appearance.showContributionHeader else { return }

        self.session.contributionUser = username
        self.session.contributionHeatmap = []
        self.session.contributionError = nil
        self.session.contributionIsLoading = false
        self.restoreGlobalActivityCacheIfPossible(username: username)
    }

    func clearContributionCache() {
        ContributionCacheStore.clear()
        self.globalActivityCacheStore.clear()
        self.session.contributionHeatmap = []
        self.session.contributionUser = nil
        self.session.contributionError = nil
    }
}
