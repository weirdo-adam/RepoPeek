import Foundation

struct GitLabReferenceIssueNumberTokenMatch {
    let query: GitLabReferenceQuery
    let tokenIndex: Int
}

private struct IssueNumberToken: Hashable {
    let number: Int
    let tokenIndex: Int
}

public enum GitLabReferenceTranslator {
    public static let defaultMinimumBareDigits = 1
    private static let maxScannedTextLength = 8000
    private static let maxIssueSeriesCount = 100

    public static func query(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits
    ) -> GitLabReferenceQuery? {
        self.queries(from: rawText, minimumBareDigits: minimumBareDigits).first
    }

    public static func queries(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits,
        repositoryContextOverride: String? = nil
    ) -> [GitLabReferenceQuery] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = self.urlQuery(from: text) {
            return [query]
        }

        if let query = self.tokenQuery(
            from: text,
            minimumBareDigits: minimumBareDigits,
            allowBareIssueNumber: true,
            allowNumericCommitHash: true
        ) {
            return [self.applyingRepositoryContext(repositoryContextOverride, to: query)]
        }

        let scannedText = rawText.trimmingCharacters(in: .newlines)
        guard scannedText.count <= Self.maxScannedTextLength else { return [] }

        let repositoryHeadingListBlockParse = self.repositoryHeadingListBlockParse(
            in: scannedText,
            minimumBareDigits: minimumBareDigits
        )
        if repositoryHeadingListBlockParse.consumedLineIndexes.isEmpty == false {
            return self.queriesMergingRepositoryHeadingListBlocks(
                in: scannedText,
                minimumBareDigits: minimumBareDigits,
                repositoryContextOverride: repositoryContextOverride,
                repositoryHeadingListBlockParse: repositoryHeadingListBlockParse
            )
        }

        return self.normalQueries(
            from: repositoryHeadingListBlockParse.remainingText,
            minimumBareDigits: minimumBareDigits,
            repositoryContextOverride: repositoryContextOverride
        )
    }

    private static func normalQueries(
        from parseText: String,
        minimumBareDigits: Int,
        repositoryContextOverride: String?
    ) -> [GitLabReferenceQuery] {
        let tokens = self.referenceTokens(in: parseText)
        let groupedQueries = self.groupedRepositoryIssueQueries(in: parseText)
        let lineScopedQueries = self.lineScopedRepositoryIssueQueries(
            in: parseText,
            minimumBareDigits: minimumBareDigits
        )
        let repositoryContext = repositoryContextOverride
            ?? self.repositoryContext(in: parseText)
            ?? self.listItemRepositoryContext(in: parseText)
        if tokens.contains(where: { self.urlQuery(from: $0) != nil }) {
            let primaryListQueries = self.primaryListItemQueries(
                in: parseText,
                repositoryContext: repositoryContext
            )
            if primaryListQueries.count >= 2 {
                return primaryListQueries
            }
        }

        var queries: [GitLabReferenceQuery] = []
        var seen: Set<String> = []
        func append(_ query: GitLabReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        for token in tokens {
            if let query = self.urlQuery(from: token) {
                append(query)
            }
            for query in self.compoundRepositoryIssueQueries(from: token) {
                append(query)
            }
        }

        for query in groupedQueries {
            append(query)
        }
        for query in lineScopedQueries {
            append(query)
        }
        for query in self.contextualBareIssueQueries(in: parseText, minimumBareDigits: minimumBareDigits) {
            append(self.applyingRepositoryContext(repositoryContext, to: query))
        }

        let allowsNumericCommitHash = self.hasCommitContext(parseText)
        for line in parseText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            for sentence in self.lineScopedSentenceFragments(in: line) {
                let lineScopedIssueTokens = self.scopedIssueNumberTokens(
                    inLine: sentence,
                    minimumBareDigits: minimumBareDigits
                )
                for (index, token) in self.referenceTokens(in: sentence).enumerated() {
                    if let query = self.tokenQuery(
                        from: token,
                        minimumBareDigits: minimumBareDigits,
                        allowBareIssueNumber: false,
                        allowNumericCommitHash: allowsNumericCommitHash
                    ) {
                        let isLineScopedIssueToken = self.issueNumber(fromQuery: query).map {
                            lineScopedIssueTokens.contains(IssueNumberToken(number: $0, tokenIndex: index))
                        } ?? false
                        if isLineScopedIssueToken {
                            continue
                        }
                        append(self.applyingRepositoryContext(repositoryContext, to: query))
                    }
                }
            }
        }

        return queries
    }

    private static func contextualBareIssueQueries(in text: String, minimumBareDigits: Int) -> [GitLabReferenceQuery] {
        var previousHadReferenceContext = false
        var queries: [GitLabReferenceQuery] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previousHadReferenceContext = false
                continue
            }

            for sentence in self.lineScopedSentenceFragments(in: line) {
                if self.isIssueCountSummary(sentence) {
                    previousHadReferenceContext = false
                    continue
                }

                let lineScopedIssueTokens = self.scopedIssueNumberTokens(
                    inLine: sentence,
                    minimumBareDigits: minimumBareDigits
                )
                let hasContext = self.hasIssueReferenceContext(sentence)
                defer { previousHadReferenceContext = hasContext }

                if hasContext {
                    queries.append(contentsOf: self.suppressLineScopedIssueDuplicates(
                        in: self.contextualBareIssueSeriesMatches(
                            in: sentence,
                            minimumBareDigits: minimumBareDigits
                        ),
                        lineScopedIssueTokens: lineScopedIssueTokens
                    ).map(\.query))
                }

                if previousHadReferenceContext, self.startsWithBackReference(sentence) {
                    queries.append(contentsOf: self.suppressLineScopedIssueDuplicates(
                        in: self.backReferenceBareIssueSeriesMatches(
                            in: sentence,
                            minimumBareDigits: minimumBareDigits
                        ),
                        lineScopedIssueTokens: lineScopedIssueTokens
                    ).map(\.query))
                }
            }
        }

        return queries
    }

    private static func suppressLineScopedIssueDuplicates(
        in matches: [GitLabReferenceIssueNumberTokenMatch],
        lineScopedIssueTokens: Set<IssueNumberToken>
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        matches.filter { match in
            guard case let .issueNumber(number) = match.query else { return true }

            return lineScopedIssueTokens.contains(IssueNumberToken(number: number, tokenIndex: match.tokenIndex)) == false
        }
    }

    private static func scopedIssueNumberTokens(inLine line: String, minimumBareDigits: Int) -> Set<IssueNumberToken> {
        Set(
            self.lineScopedRepositoryIssueNumberTokenMatches(
                inLine: line,
                minimumBareDigits: minimumBareDigits
            )
            .compactMap { match in
                guard let number = self.issueNumber(fromQuery: match.query) else { return nil }

                return IssueNumberToken(number: number, tokenIndex: match.tokenIndex)
            }
        )
    }

    private static func contextualBareIssueSeriesMatches(
        in sentence: String,
        minimumBareDigits: Int
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        let tokens = self.referenceTokens(in: sentence)
        guard tokens.isEmpty == false else { return [] }

        var matches: [GitLabReferenceIssueNumberTokenMatch] = []
        for index in tokens.indices {
            let token = tokens[index].lowercased()
            if index > tokens.startIndex, self.isRepositoryFullName(tokens[tokens.index(before: index)]) {
                continue
            }
            let nextToken = tokens.indices.contains(index + 1) ? tokens[index + 1].lowercased() : nil
            let startIndex: Int? = if ["mr", "mrs", "pr", "prs", "issue", "issues"].contains(token) {
                index + 1
            } else if token == "merge", nextToken == "request" || nextToken == "requests" {
                index + 2
            } else if token == "pull", nextToken == "request" || nextToken == "requests" {
                index + 2
            } else {
                nil
            }
            guard let startIndex else { continue }

            matches.append(contentsOf: self.bareIssueSeriesMatches(
                in: Array(tokens.dropFirst(startIndex)),
                minimumBareDigits: minimumBareDigits,
                tokenOffset: startIndex
            ))
        }

        return matches
    }

    private static func backReferenceBareIssueSeriesQueries(in sentence: String, minimumBareDigits: Int) -> [GitLabReferenceQuery] {
        self.backReferenceBareIssueSeriesMatches(in: sentence, minimumBareDigits: minimumBareDigits).map(\.query)
    }

    private static func backReferenceBareIssueSeriesMatches(
        in sentence: String,
        minimumBareDigits: Int
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        let tokens = self.referenceTokens(in: sentence)
        guard tokens.count >= 2 else { return [] }

        let firstToken = tokens[0].lowercased()
        guard ["that", "this", "it", "they", "these", "those"].contains(firstToken) else { return [] }

        let firstSeriesIndex = ["is", "are", "was", "were"].contains(tokens[1].lowercased()) ? 2 : 1
        guard tokens.indices.contains(firstSeriesIndex) else { return [] }

        return self.bareIssueSeriesMatches(
            in: Array(tokens.dropFirst(firstSeriesIndex)),
            minimumBareDigits: minimumBareDigits,
            tokenOffset: firstSeriesIndex
        )
    }

    private static func bareIssueSeriesQueries(in tokens: [String], minimumBareDigits: Int) -> [GitLabReferenceQuery] {
        self.bareIssueSeriesMatches(in: tokens, minimumBareDigits: minimumBareDigits).map(\.query)
    }

    static func bareIssueSeriesMatches(
        in tokens: [String],
        minimumBareDigits: Int,
        tokenOffset: Int = 0
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        var matches: [GitLabReferenceIssueNumberTokenMatch] = []

        for index in tokens.indices {
            let token = tokens[index]
            let normalized = token.lowercased()
            if let number = self.bareIssueSeriesNumber(from: token, minimumBareDigits: minimumBareDigits) {
                let startsDiffStat = token.hasPrefix("#") == false && self.startsDiffStat(in: tokens, at: index)
                if startsDiffStat, matches.isEmpty == false {
                    break
                }
                matches.append(GitLabReferenceIssueNumberTokenMatch(
                    query: .issueNumber(number),
                    tokenIndex: tokenOffset + index
                ))
                if startsDiffStat {
                    break
                }
                continue
            }

            if ["and", "or", "maybe"].contains(normalized) {
                continue
            }

            break
        }

        return matches
    }

    static func issueNumber(fromQuery query: GitLabReferenceQuery) -> Int? {
        switch query {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            number
        case .commitHash, .repositoryCommitHash, .repositoryWorkflowRun:
            nil
        }
    }

    private static func startsDiffStat(in tokens: [String], at index: Array<String>.Index) -> Bool {
        let nounIndex = index + 1
        guard tokens.indices.contains(nounIndex),
              self.isDiffStatNoun(tokens[nounIndex].lowercased())
        else { return false }

        let nextIndex = nounIndex + 1
        let noun = tokens[nounIndex].lowercased()
        guard tokens.indices.contains(nextIndex) else {
            return self.isStrongDiffStatNoun(noun)
        }

        let nextToken = tokens[nextIndex].lowercased()
        if nextToken == "/" {
            let countIndex = nextIndex + 1
            return tokens.indices.contains(countIndex) && Int(tokens[countIndex]) != nil
        }
        if nextToken == "changed" {
            return self.isStrongDiffStatNoun(noun)
        }
        if ["and", "or"].contains(nextToken) {
            let countIndex = nextIndex + 1
            return self.isStrongDiffStatNoun(noun) &&
                tokens.indices.contains(countIndex) &&
                Int(tokens[countIndex]) != nil
        }

        return Int(nextToken) != nil && self.isStrongDiffStatNoun(noun)
    }

    private static func isDiffStatNoun(_ token: String) -> Bool {
        [
            "add",
            "adds",
            "addition",
            "additions",
            "del",
            "dels",
            "delete",
            "deletes",
            "deletion",
            "deletions",
            "file",
            "files"
        ].contains(token)
    }

    private static func isStrongDiffStatNoun(_ token: String) -> Bool {
        [
            "addition",
            "additions",
            "deletion",
            "deletions",
            "file",
            "files"
        ].contains(token)
    }

    private static func bareIssueSeriesNumber(from token: String, minimumBareDigits: Int) -> Int? {
        if token.hasPrefix("#") {
            return self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: false)
        }
        if token.lowercased().hasPrefix("gl-") {
            return self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: false)
        }

        guard token.allSatisfy(\.isNumber),
              let number = self.issueNumber(
                  from: token,
                  minimumBareDigits: minimumBareDigits,
                  allowBareNumber: true
              )
        else { return nil }

        return number
    }

    private static func primaryListItemQueries(
        in text: String,
        repositoryContext: String?
    ) -> [GitLabReferenceQuery] {
        let allowsNumericCommitHash = self.hasCommitContext(text)
        var queries: [GitLabReferenceQuery] = []
        var seen: Set<String> = []

        func append(_ query: GitLabReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let body = self.listItemBody(in: line),
                  let firstToken = self.referenceTokens(in: body).first
            else { continue }

            if let query = self.urlQuery(from: firstToken) {
                append(query)
                continue
            }

            let compoundQueries = self.compoundRepositoryIssueQueries(from: firstToken)
            if compoundQueries.isEmpty == false {
                compoundQueries.forEach(append)
                continue
            }

            guard let query = self.tokenQuery(
                from: firstToken,
                minimumBareDigits: 1,
                allowBareIssueNumber: false,
                allowNumericCommitHash: allowsNumericCommitHash
            ) else { continue }

            append(self.applyingRepositoryContext(repositoryContext, to: query))
        }

        return queries
    }

    private static func listItemBody(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var digitEnd = trimmed.startIndex
        while digitEnd < trimmed.endIndex, trimmed[digitEnd].isNumber {
            digitEnd = trimmed.index(after: digitEnd)
        }
        guard digitEnd > trimmed.startIndex,
              digitEnd < trimmed.endIndex,
              trimmed[digitEnd] == "." || trimmed[digitEnd] == ")"
        else { return nil }

        let markerEnd = trimmed.index(after: digitEnd)
        guard markerEnd == trimmed.endIndex || trimmed[markerEnd].isWhitespace else { return nil }

        return String(trimmed[markerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenQuery(
        from rawToken: String,
        minimumBareDigits: Int,
        allowBareIssueNumber: Bool,
        allowNumericCommitHash: Bool
    ) -> GitLabReferenceQuery? {
        let token = self.normalizedToken(from: rawToken)
        guard token.isEmpty == false else { return nil }

        if let scopedIssue = self.repositoryIssueNumber(from: token) {
            return scopedIssue
        }
        if let namedIssue = self.repositoryNameIssueNumber(from: token) {
            return namedIssue
        }
        if self.isCommitHash(token, allowNumericOnly: allowNumericCommitHash) {
            return .commitHash(token.lowercased())
        }
        if let number = self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: allowBareIssueNumber) {
            return .issueNumber(number)
        }
        return nil
    }

    private static func urlQuery(from rawText: String) -> GitLabReferenceQuery? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased().hasPrefix("http") == true
        else { return nil }

        let host = components.host?.lowercased() ?? ""
        guard host == "gitlab.com" || host.hasSuffix(".gitlab.com") else { return nil }

        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
        guard let routeSeparator = pathParts.firstIndex(of: "-"),
              routeSeparator >= 2,
              pathParts.count > routeSeparator + 2
        else { return nil }

        let repositoryFullName = pathParts[..<routeSeparator].joined(separator: "/")
        let route = pathParts[routeSeparator + 1].lowercased()
        let routeParts = Array(pathParts.dropFirst(routeSeparator + 2))
        guard let firstRoutePart = routeParts.first else { return nil }

        switch route {
        case "issues":
            guard let number = Int(firstRoutePart) else { return nil }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case "merge_requests":
            if let hash = self.commitHash(in: routeParts.dropFirst()) {
                return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
            }
            guard let number = Int(firstRoutePart) else { return nil }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case "commit", "commits":
            let hash = firstRoutePart.lowercased()
            guard self.isCommitHash(hash, allowNumericOnly: true) else { return nil }

            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        case "pipelines":
            guard let runID = Int64(firstRoutePart)
            else { return nil }

            return .repositoryWorkflowRun(repositoryFullName: repositoryFullName, runID: runID)
        default:
            guard let hash = self.commitHash(in: routeParts) else { return nil }

            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        }
    }

    private static func commitHash(in pathParts: some Sequence<String>) -> String? {
        pathParts
            .map { $0.lowercased() }
            .first { self.isCommitHash($0, allowNumericOnly: true) }
    }

    static func issueNumber(from token: String, minimumBareDigits: Int, allowBareNumber: Bool) -> Int? {
        if token.hasPrefix("#") {
            return Int(token.dropFirst())
        }
        if token.lowercased().hasPrefix("gl-") {
            return Int(token.dropFirst(3))
        }
        guard allowBareNumber else { return nil }
        guard token.count >= minimumBareDigits,
              token.allSatisfy(\.isNumber)
        else { return nil }

        return Int(token)
    }

    private static func repositoryIssueNumber(from token: String) -> GitLabReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryFullName(parts[0])
        else { return nil }

        return .repositoryIssueNumber(repositoryFullName: parts[0], number: number)
    }

    private static func repositoryNameIssueNumber(from token: String) -> GitLabReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryName(parts[0])
        else { return nil }

        return .repositoryNameIssueNumber(repositoryName: parts[0], number: number)
    }

    private static func compoundRepositoryIssueQueries(from token: String) -> [GitLabReferenceQuery] {
        let parts = token.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              self.isRepositoryFullName(parts[0]),
              parts[1].contains("/") || parts[1].contains("-")
        else { return [] }

        let numberParts = parts[1]
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard numberParts.isEmpty == false else { return [] }

        var numbers: [Int] = []
        for numberPart in numberParts {
            guard let parsedNumbers = self.issueNumbers(fromSeriesPart: numberPart)
            else { return [] }

            numbers.append(contentsOf: parsedNumbers)
        }
        guard (1 ... Self.maxIssueSeriesCount).contains(numbers.count) else { return [] }

        return numbers.map { .repositoryIssueNumber(repositoryFullName: parts[0], number: $0) }
    }

    private static func issueNumbers(fromSeriesPart rawPart: String) -> [Int]? {
        let part = rawPart.hasPrefix("#") ? String(rawPart.dropFirst()) : rawPart
        guard part.isEmpty == false else { return nil }

        let rangeParts = part
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        if rangeParts.count == 2 {
            guard let start = self.issueSeriesNumber(from: rangeParts[0]),
                  let end = self.issueSeriesNumber(from: rangeParts[1]),
                  start <= end
            else { return nil }

            return Array(start ... end)
        }

        guard let number = self.issueSeriesNumber(from: part) else { return nil }

        return [number]
    }

    private static func issueSeriesNumber(from rawNumber: String) -> Int? {
        let normalized = rawNumber.hasPrefix("#") ? String(rawNumber.dropFirst()) : rawNumber
        guard normalized.isEmpty == false,
              normalized.allSatisfy(\.isNumber)
        else { return nil }

        return Int(normalized)
    }

    static func isRepositoryFullName(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }

        return parts.allSatisfy { part in
            part.isEmpty == false && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
            }
        }
    }

    private static func isRepositoryName(_ value: String) -> Bool {
        value.isEmpty == false && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }

    private static func repositoryContext(in text: String) -> String? {
        var repositoryFullNames: [String] = []
        var seen: Set<String> = []

        func append(_ repositoryFullName: String) {
            guard seen.insert(repositoryFullName.lowercased()).inserted else { return }

            repositoryFullNames.append(repositoryFullName)
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let lineScopedRepositories = Set(
                self.lineScopedRepositoryIssueQueries(inLine: line, minimumBareDigits: 1)
                    .compactMap(\.repositoryFullName)
                    .map { $0.lowercased() }
            )
            let tokens = self.referenceTokens(in: line)
            for (index, token) in tokens.enumerated() {
                let isProseRepositoryContext = token.contains("#") == false
                    && self.isRepositoryFullName(token)
                    && lineScopedRepositories.contains(token.lowercased()) == false
                    && self.isLikelyRepositoryContextToken(at: index, in: tokens)
                if isProseRepositoryContext {
                    append(token)
                    continue
                }
                if let repositoryFullName = self.urlQuery(from: token)?.repositoryFullName {
                    append(repositoryFullName)
                    continue
                }
                if let repositoryFullName = self.repositoryIssueNumber(from: token)?.repositoryFullName {
                    append(repositoryFullName)
                }
            }
        }

        return repositoryFullNames.count == 1 ? repositoryFullNames[0] : nil
    }

    private static func listItemRepositoryContext(in text: String) -> String? {
        let repositories = text
            .split(whereSeparator: \.isNewline)
            .compactMap { self.listItemBody(in: String($0)) }
            .compactMap { body -> String? in
                let tokens = self.referenceTokens(in: body)
                guard tokens.count == 1,
                      let repositoryFullName = tokens.first,
                      self.isRepositoryFullName(repositoryFullName)
                else { return nil }

                return repositoryFullName
            }

        var uniqueRepositories: [String] = []
        var seen: Set<String> = []
        for repository in repositories {
            guard seen.insert(repository.lowercased()).inserted else { continue }

            uniqueRepositories.append(repository)
        }

        return uniqueRepositories.count == 1 ? uniqueRepositories[0] : nil
    }

    private static func isLikelyRepositoryContextToken(at index: Int, in tokens: [String]) -> Bool {
        guard tokens.indices.contains(index) else { return false }
        guard index > 0 else { return true }

        let previous = tokens[index - 1].lowercased()
        return ["in", "repo", "repository", "from", "for", "on", "inside"].contains(previous)
    }

    private static func hasIssueReferenceContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let tokens = self.referenceTokens(in: normalized)
        if tokens.contains(where: { ["mr", "mrs", "pr", "prs", "issue", "issues"].contains($0) }) {
            return true
        }

        return normalized.contains("merge request")
            || normalized.contains("pull request")
            || normalized.contains("security fix")
            || normalized.contains("fix/enhancement")
    }

    private static func startsWithBackReference(_ text: String) -> Bool {
        guard let firstToken = self.referenceTokens(in: text).first?.lowercased() else { return false }

        return ["that", "this", "it", "they", "these", "those"].contains(firstToken)
    }

    private static func applyingRepositoryContext(_ repositoryFullName: String?, to query: GitLabReferenceQuery) -> GitLabReferenceQuery {
        guard let repositoryFullName else { return query }

        switch query {
        case let .issueNumber(number):
            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .repositoryNameIssueNumber(repositoryName, number):
            guard repositoryFullName.split(separator: "/").last?.caseInsensitiveCompare(repositoryName) == .orderedSame else {
                return query
            }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .commitHash(hash):
            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        case .repositoryIssueNumber, .repositoryCommitHash, .repositoryWorkflowRun:
            return query
        }
    }

    private static func normalizedToken(from rawToken: String) -> String {
        rawToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}<>\"'`"))
    }

    static func referenceTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(self.normalizedToken)
            .filter { $0.isEmpty == false }
    }

    private static func hasCommitContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("sha") || normalized.contains("commit") || normalized.contains("hash")
    }

    private static func dedupeKey(for query: GitLabReferenceQuery) -> String {
        switch query {
        case let .issueNumber(number):
            "issue:\(number)"
        case let .repositoryNameIssueNumber(repositoryName, number):
            "repo-name:\(repositoryName.lowercased())#\(number)"
        case let .repositoryIssueNumber(repositoryFullName, number):
            "repo:\(repositoryFullName.lowercased())#\(number)"
        case let .commitHash(hash):
            "commit:\(hash.lowercased())"
        case let .repositoryCommitHash(repositoryFullName, hash):
            "repo:\(repositoryFullName.lowercased())@\(hash.lowercased())"
        case let .repositoryWorkflowRun(repositoryFullName, runID):
            "repo:\(repositoryFullName.lowercased())/run/\(runID)"
        }
    }

    private static func isCommitHash(_ token: String, allowNumericOnly: Bool) -> Bool {
        guard (7 ... 40).contains(token.count) else { return false }
        guard token.allSatisfy(\.isHexDigit) else { return false }
        guard allowNumericOnly || token.contains(where: \.isLetter) else { return false }

        return true
    }
}

private struct RepositoryHeadingListBlockParse {
    let entries: [RepositoryHeadingListBlockEntry]
    let consumedLineIndexes: Set<Int>
    let remainingText: String
}

private struct RepositoryHeadingListBlockEntry {
    let lineIndex: Int
    let queries: [GitLabReferenceQuery]
}

private extension GitLabReferenceTranslator {
    static func repositoryHeadingListBlockParse(
        in text: String,
        minimumBareDigits: Int
    ) -> RepositoryHeadingListBlockParse {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entries: [RepositoryHeadingListBlockEntry] = []
        var consumedLineIndexes: Set<Int> = []
        var currentRepositoryFullName: String?
        var currentHeadingIndent: Int?
        var currentChildHadIssueReferenceContext = false
        var currentChildHadCommitContext = false
        var pendingRepositoryFullName: String?
        var pendingHeadingIndent: Int?
        var pendingLineIndex: Int?

        func clearCurrentBlock() {
            currentRepositoryFullName = nil
            currentHeadingIndent = nil
            currentChildHadIssueReferenceContext = false
            currentChildHadCommitContext = false
        }

        func clearPendingBlock() {
            pendingRepositoryFullName = nil
            pendingHeadingIndent = nil
            pendingLineIndex = nil
        }

        for (lineIndex, line) in lines.enumerated() {
            let indent = self.leadingWhitespaceCount(in: line)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let listItemBody = self.listItemBody(in: line)
            let bodyOrTrimmed = listItemBody ?? trimmed

            if let repositoryFullName = self.repositoryHeading(in: bodyOrTrimmed) {
                clearPendingBlock()
                currentRepositoryFullName = repositoryFullName
                currentHeadingIndent = indent
                currentChildHadIssueReferenceContext = false
                currentChildHadCommitContext = false
                consumedLineIndexes.insert(lineIndex)
                continue
            }

            if let pendingFullName = pendingRepositoryFullName {
                let pendingIndent = pendingHeadingIndent ?? indent
                let pendingIndex = pendingLineIndex ?? lineIndex
                if trimmed.isEmpty || indent <= pendingIndent {
                    clearPendingBlock()
                } else if self.isIssueCountSummary(bodyOrTrimmed) {
                    currentRepositoryFullName = pendingFullName
                    currentHeadingIndent = pendingIndent
                    currentChildHadIssueReferenceContext = false
                    currentChildHadCommitContext = false
                    consumedLineIndexes.insert(pendingIndex)
                    consumedLineIndexes.insert(lineIndex)
                    clearPendingBlock()
                    continue
                } else {
                    clearPendingBlock()
                }
            }

            let canStartRepositoryOnlyHeading = currentHeadingIndent.map { indent <= $0 } ?? true
            if canStartRepositoryOnlyHeading,
               let repositoryFullName = self.repositoryOnlyHeading(in: bodyOrTrimmed)
            {
                clearCurrentBlock()
                pendingRepositoryFullName = repositoryFullName
                pendingHeadingIndent = indent
                pendingLineIndex = lineIndex
                continue
            }

            if let repositoryFullName = currentRepositoryFullName,
               let headingIndent = currentHeadingIndent
            {
                if trimmed.isEmpty || indent <= headingIndent {
                    clearCurrentBlock()
                    continue
                }

                let childText = listItemBody ?? trimmed
                let lineQueries = self.leadingRepositoryHeadingQueries(
                    in: childText,
                    repositoryFullName: repositoryFullName,
                    minimumBareDigits: minimumBareDigits,
                    previousHadCommitContext: currentChildHadCommitContext,
                    previousHadIssueReferenceContext: currentChildHadIssueReferenceContext
                )
                currentChildHadIssueReferenceContext = self.headingChildHasIssueReferenceContext(childText)
                currentChildHadCommitContext = self.headingChildHasCommitContext(childText)
                consumedLineIndexes.insert(lineIndex)
                if lineQueries.isEmpty == false {
                    entries.append(RepositoryHeadingListBlockEntry(lineIndex: lineIndex, queries: lineQueries))
                }
                continue
            }

            if listItemBody != nil {
                clearCurrentBlock()
            }
        }

        let remainingText = lines.enumerated()
            .map { consumedLineIndexes.contains($0.offset) ? "" : $0.element }
            .joined(separator: "\n")

        return RepositoryHeadingListBlockParse(
            entries: entries,
            consumedLineIndexes: consumedLineIndexes,
            remainingText: remainingText
        )
    }

    static func queriesMergingRepositoryHeadingListBlocks(
        in text: String,
        minimumBareDigits: Int,
        repositoryContextOverride: String?,
        repositoryHeadingListBlockParse: RepositoryHeadingListBlockParse
    ) -> [GitLabReferenceQuery] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let entriesByLine = Dictionary(grouping: repositoryHeadingListBlockParse.entries, by: \.lineIndex)
        var normalLines: [String] = []
        var queries: [GitLabReferenceQuery] = []
        var seen: Set<String> = []

        func append(_ query: GitLabReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        func flushNormalLines() {
            guard normalLines.isEmpty == false else { return }

            let chunkText = normalLines.joined(separator: "\n")
            for query in self.normalQueries(
                from: chunkText,
                minimumBareDigits: minimumBareDigits,
                repositoryContextOverride: repositoryContextOverride
            ) {
                append(query)
            }
            normalLines.removeAll(keepingCapacity: true)
        }

        for lineIndex in lines.indices {
            if repositoryHeadingListBlockParse.consumedLineIndexes.contains(lineIndex) {
                flushNormalLines()
                for entry in entriesByLine[lineIndex] ?? [] {
                    for query in entry.queries {
                        append(query)
                    }
                }
                continue
            }

            normalLines.append(lines[lineIndex])
        }
        flushNormalLines()

        return queries
    }

    static func isIssueCountSummary(_ text: String) -> Bool {
        let tokens = self.referenceTokens(in: text.lowercased())
        guard tokens.isEmpty == false else { return false }

        var hasIssueCount = false
        var hasMergeRequestCount = false
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "/" {
                index = tokens.index(after: index)
                continue
            }

            guard Int(token) != nil else { return false }

            index = tokens.index(after: index)
            guard index < tokens.endIndex else { return false }

            let noun = tokens[index]
            if noun == "issue" || noun == "issues" {
                hasIssueCount = true
                index = tokens.index(after: index)
                continue
            }
            if ["mr", "mrs", "pr", "prs"].contains(noun) {
                hasMergeRequestCount = true
                index = tokens.index(after: index)
                continue
            }
            if self.startsRequestPhrase(tokens: tokens, index: index, lead: "merge") ||
                self.startsRequestPhrase(tokens: tokens, index: index, lead: "pull")
            {
                hasMergeRequestCount = true
                index = tokens.index(index, offsetBy: 2)
                continue
            }
            return false
        }

        return hasIssueCount && hasMergeRequestCount
    }

    static func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix(while: \.isWhitespace).count
    }

    static func repositoryHeading(in listItemBody: String) -> String? {
        guard let colon = listItemBody.firstIndex(of: ":") else { return nil }

        let suffix = String(listItemBody[listItemBody.index(after: colon)...])
        guard self.isIssueCountSummary(suffix) else { return nil }

        let suffixTokens = self.referenceTokens(in: suffix)
        guard suffixTokens.contains(where: {
            self.issueNumber(from: $0, minimumBareDigits: 1, allowBareNumber: false) != nil
        }) == false else { return nil }

        let prefixTokens = self.referenceTokens(in: String(listItemBody[..<colon]))
        guard prefixTokens.count == 1,
              let repositoryFullName = prefixTokens.first,
              self.isRepositoryFullName(repositoryFullName)
        else { return nil }

        return repositoryFullName
    }

    static func repositoryOnlyHeading(in listItemBody: String) -> String? {
        let trimmed = listItemBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(":") == false else { return nil }

        let tokens = self.referenceTokens(in: trimmed)
        guard tokens.count == 1,
              let repositoryFullName = tokens.first,
              self.isRepositoryFullName(repositoryFullName)
        else { return nil }

        return repositoryFullName
    }

    static func leadingRepositoryHeadingQueries(
        in line: String,
        repositoryFullName: String,
        minimumBareDigits: Int,
        previousHadCommitContext: Bool,
        previousHadIssueReferenceContext: Bool
    ) -> [GitLabReferenceQuery] {
        guard self.isIssueCountSummary(line) == false else { return [] }

        let allowsCommitHash = previousHadCommitContext || self.headingChildHasCommitContext(line)
        let tokenQueries = self.referenceTokens(in: line).flatMap { token in
            self.repositoryHeadingTokenQueries(
                token,
                repositoryFullName: repositoryFullName,
                allowsCommitHash: allowsCommitHash
            )
        }
        let contextualQueries = self.contextualBareIssueQueries(
            in: line,
            minimumBareDigits: minimumBareDigits
        )
        .map { self.applyingRepositoryContext(repositoryFullName, to: $0) }
        let backReferenceQueries = previousHadIssueReferenceContext
            ? self.backReferenceBareIssueSeriesQueries(in: line, minimumBareDigits: minimumBareDigits)
            .map { self.applyingRepositoryContext(repositoryFullName, to: $0) }
            : []

        return self.dedupedQueries(tokenQueries + contextualQueries + backReferenceQueries)
    }

    static func repositoryHeadingTokenQueries(
        _ token: String,
        repositoryFullName: String,
        allowsCommitHash: Bool
    ) -> [GitLabReferenceQuery] {
        let compoundQueries = self.compoundRepositoryIssueQueries(from: token)
        if compoundQueries.isEmpty == false {
            return compoundQueries
        }

        if let query = self.urlQuery(from: token) {
            return [query]
        }
        if let query = self.tokenQuery(
            from: token,
            minimumBareDigits: 1,
            allowBareIssueNumber: false,
            allowNumericCommitHash: allowsCommitHash
        ) {
            if case .commitHash = query, allowsCommitHash == false {
                return []
            }
            return [self.applyingRepositoryContext(repositoryFullName, to: query)]
        }
        return []
    }

    static func headingChildHasIssueReferenceContext(_ line: String) -> Bool {
        let lastSentence = line
            .split { character in
                character == "." || character == "!" || character == "?"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { $0.isEmpty == false }
        guard let lastSentence else { return false }

        return self.isIssueCountSummary(lastSentence) == false && self.hasIssueReferenceContext(lastSentence)
    }

    static func headingChildHasCommitContext(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.contains("sha") || normalized.contains("commit") || normalized.contains("hash")
    }

    static func startsRequestPhrase(tokens: [String], index: Array<String>.Index, lead: String) -> Bool {
        tokens[index] == lead &&
            tokens.indices.contains(tokens.index(after: index)) &&
            ["request", "requests"].contains(tokens[tokens.index(after: index)])
    }

    static func dedupedQueries(_ queries: [GitLabReferenceQuery]) -> [GitLabReferenceQuery] {
        var seen: Set<String> = []
        return queries.filter { seen.insert(self.dedupeKey(for: $0)).inserted }
    }
}
