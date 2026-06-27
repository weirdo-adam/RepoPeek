import Foundation
import RepoPeekCore

extension AppState {
    func fetchActivityRepos() async throws -> [Repository] {
        let accounts = self.enabledGitLabAccountsWithTokens()
        guard accounts.isEmpty == false else { throw URLError(.userAuthenticationRequired) }

        var repos: [Repository] = []
        var firstError: Error?

        for account in accounts {
            let client = await self.gitLabClient(for: account)
            do {
                let accountRepos = try await client.repositoryList(limit: nil)
                    .map { self.repository($0, applyingHostFrom: account) }
                repos.append(contentsOf: accountRepos)
                self.session.accountErrors[account.accountID] = nil
            } catch {
                firstError = firstError ?? error
                self.session.accountErrors[account.accountID] = error.userFacingMessage
            }
        }

        if repos.isEmpty, let firstError {
            throw firstError
        }
        return self.applyPinnedOrder(to: repos)
    }

    func fetchGlobalActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        repos: [Repository]
    ) async -> GlobalActivityResult {
        let accounts = self.enabledGitLabAccountsWithTokens()
        var userEvents: [ActivityEvent] = []
        var firstError: Error?
        let range = self.session.heatmapRange
        let calendar = HeatmapFilter.gitLabCalendar()

        for account in accounts {
            let client = await self.gitLabClient(for: account)
            let accountUsername = self.session.accountUsers[account.accountID]?.username ?? account.username ?? username
            let cache = self.globalActivityCacheStore.load(
                hostKey: account.hostKey,
                username: accountUsername,
                scope: scope
            )
            let fetchPlan = GlobalActivityCachePlanner.fetchPlan(
                cache: cache,
                range: range,
                calendar: calendar
            )
            do {
                let fetchedEvents = try await client.userActivityEvents(
                    username: accountUsername,
                    scope: scope,
                    after: fetchPlan.after,
                    before: fetchPlan.before,
                    limit: AppLimits.GlobalActivity.heatmapFetchLimit
                )
                let nextCache = GlobalActivityCachePlanner.mergedCache(
                    cache: cache,
                    fetchedEvents: fetchedEvents,
                    hostKey: account.hostKey,
                    username: accountUsername,
                    scope: scope,
                    range: range,
                    fetchedAt: Date(),
                    calendar: calendar
                )
                self.globalActivityCacheStore.save(nextCache)
                userEvents.append(contentsOf: GlobalActivityCachePlanner.events(
                    in: nextCache.events,
                    range: range,
                    calendar: calendar
                ))
                self.session.accountErrors[account.accountID] = nil
            } catch {
                firstError = firstError ?? error
                userEvents.append(contentsOf: fetchPlan.cachedEvents)
                self.session.accountErrors[account.accountID] = error.userFacingMessage
            }
        }

        let repoEvents = GlobalActivityMerger.repositoryEvents(from: repos)
        let merged = GlobalActivityMerger.merge(
            userEvents: userEvents,
            repoEvents: userEvents.isEmpty ? repoEvents : [],
            scope: scope,
            username: username,
            limit: AppLimits.GlobalActivity.heatmapFetchLimit
        )
        return GlobalActivityResult(
            events: merged,
            commits: [],
            error: userEvents.isEmpty ? firstError?.userFacingMessage : nil,
            commitError: nil
        )
    }

    func restoreGlobalActivityCacheIfPossible(username fallbackUsername: String? = nil) {
        let accounts = self.enabledGitLabAccountsWithTokens()
        guard accounts.isEmpty == false else { return }

        let scope = self.session.settings.appearance.activityScope
        let range = self.session.heatmapRange
        let calendar = HeatmapFilter.gitLabCalendar()
        let primaryUsername = fallbackUsername
            ?? self.currentActivityUsername()
            ?? accounts.compactMap(\.username).first
        var cachedEvents: [ActivityEvent] = []

        for account in accounts {
            let accountUsername = self.session.accountUsers[account.accountID]?.username
                ?? account.username
                ?? primaryUsername
            guard let accountUsername,
                  let cache = self.globalActivityCacheStore.load(
                      hostKey: account.hostKey,
                      username: accountUsername,
                      scope: scope
                  )
            else { continue }

            cachedEvents.append(contentsOf: GlobalActivityCachePlanner.events(
                in: cache.events,
                range: range,
                calendar: calendar
            ))
        }

        guard cachedEvents.isEmpty == false else { return }

        let merged = GlobalActivityMerger.merge(
            userEvents: cachedEvents,
            repoEvents: [],
            scope: scope,
            username: primaryUsername ?? "",
            limit: AppLimits.GlobalActivity.heatmapFetchLimit
        )
        guard merged.isEmpty == false, merged != self.session.globalActivityEvents else { return }

        self.session.globalActivityEvents = merged
        self.session.globalActivityError = nil
        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
    }

    private func currentActivityUsername() -> String? {
        guard case let .loggedIn(user) = self.session.account,
              user.username.isEmpty == false
        else { return nil }

        return user.username
    }
}
