import Foundation

extension Notification.Name {
    static let menuFiltersDidChange = Notification.Name("menuFiltersDidChange")
    static let menuRepositoriesDidChange = Notification.Name("menuRepositoriesDidChange")
    static let menuDiagnosticsDidChange = Notification.Name("menuDiagnosticsDidChange")
    static let recentListFiltersDidChange = Notification.Name("recentListFiltersDidChange")
    static let gitLabReferenceMatchDidChange = Notification.Name("gitLabReferenceMatchDidChange")
    static let issueNavigatorUseClipboard = Notification.Name("issueNavigatorUseClipboard")
    static let issueNavigatorRefresh = Notification.Name("issueNavigatorRefresh")
    static let issueNavigatorCopy = Notification.Name("issueNavigatorCopy")
    static let issueNavigatorOpen = Notification.Name("issueNavigatorOpen")
    static let issueNavigatorOpenRequested = Notification.Name("issueNavigatorOpenRequested")
    static let notificationBrowserOpenRequested = Notification.Name("notificationBrowserOpenRequested")
}
