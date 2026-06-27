import Foundation

struct RepoWebURLBuilder {
    let host: URL

    func repoURL(fullName: String) -> URL? {
        let parts = self.projectPathComponents(fullName)
        guard parts.count >= 2 else { return nil }

        return self.repoPathURL(components: parts)
    }

    func repoPathURL(fullName: String, path: String) -> URL? {
        let components = path.split(separator: "/").map(String.init)
        return self.repoPathURL(fullName: fullName, components: self.gitLabRouteComponents(for: components))
    }

    func issuesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "issues"])
    }

    func pullsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "merge_requests"])
    }

    func pipelinesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "pipelines"])
    }

    func tagsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "tags"])
    }

    func branchesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "branches"])
    }

    func contributorsURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "graphs"])
    }

    func releasesURL(fullName: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "releases"])
    }

    func tagURL(fullName: String, tag: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "tree"] + tag.split(separator: "/").map(String.init))
    }

    func branchURL(fullName: String, branch: String) -> URL? {
        self.repoPathURL(fullName: fullName, components: ["-", "tree"] + branch.split(separator: "/").map(String.init))
    }

    private func repoPathURL(fullName: String, components: [String]) -> URL? {
        guard var url = self.repoURL(fullName: fullName) else { return nil }

        for component in components where component.isEmpty == false {
            url.appendPathComponent(component)
        }
        return url
    }

    private func repoPathURL(components: [String]) -> URL {
        var url = self.host
        for component in components where component.isEmpty == false {
            url.appendPathComponent(component)
        }
        return url
    }

    private func projectPathComponents(_ fullName: String) -> [String] {
        fullName.split(separator: "/").map(String.init).filter { $0.isEmpty == false }
    }

    private func gitLabRouteComponents(for components: [String]) -> [String] {
        switch components {
        case ["issues"]:
            ["-", "issues"]
        case ["pulls"], ["merge_requests"]:
            ["-", "merge_requests"]
        case ["pipelines"]:
            ["-", "pipelines"]
        case ["releases"]:
            ["-", "releases"]
        case ["tags"]:
            ["-", "tags"]
        case ["branches"]:
            ["-", "branches"]
        case ["commits"]:
            ["-", "commits"]
        case ["graphs", "contributors"]:
            ["-", "graphs"]
        default:
            components
        }
    }
}
