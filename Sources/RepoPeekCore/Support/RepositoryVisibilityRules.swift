import Foundation

public enum RepositoryVisibilityRules {
    public static func normalizeRepositoryPath(_ value: String) -> String {
        self.normalizePath(value)
    }

    public static func normalizeGroupPath(_ value: String) -> String {
        self.normalizePath(value)
    }

    public static func normalizedGroupPaths(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = self.normalizeGroupPath(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }

            return normalized
        }
    }

    public static func hiddenGroup(
        for fullName: String,
        hiddenGroups: [String]
    ) -> String? {
        let repositoryPath = self.normalizeRepositoryPath(fullName)
        guard !repositoryPath.isEmpty else { return nil }

        return self.normalizedGroupPaths(hiddenGroups).first { group in
            repositoryPath.hasPrefix("\(group)/")
        }
    }

    public static func isHidden(
        fullName: String,
        hiddenRepositories: Set<String>,
        hiddenGroups: [String]
    ) -> Bool {
        let repositoryPath = self.normalizeRepositoryPath(fullName)
        guard !repositoryPath.isEmpty else { return false }

        let hiddenRepositorySet = Set(hiddenRepositories.map { self.normalizeRepositoryPath($0) })
        return hiddenRepositorySet.contains(repositoryPath)
            || self.hiddenGroup(for: repositoryPath, hiddenGroups: hiddenGroups) != nil
    }

    private static func normalizePath(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
            .lowercased()
    }
}
