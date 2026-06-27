import Foundation

extension GitLabReferenceTranslator {
    static func groupedRepositoryIssueQueries(in text: String) -> [GitLabReferenceQuery] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { self.groupedRepositoryIssueQueries(inLine: String($0)) }
    }

    private static func groupedRepositoryIssueQueries(inLine line: String) -> [GitLabReferenceQuery] {
        guard let colon = line.firstIndex(of: ":") else { return [] }

        let prefixTokens = self.referenceTokens(in: String(line[..<colon]))
        guard let repositoryFullName = prefixTokens.last(where: self.isRepositoryFullName) else { return [] }

        return self.referenceTokens(in: String(line[line.index(after: colon)...]))
            .compactMap { token in
                guard let number = self.issueNumber(from: token, minimumBareDigits: 1, allowBareNumber: false) else {
                    return nil
                }

                return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
            }
    }

    static func lineScopedRepositoryIssueQueries(in text: String, minimumBareDigits: Int) -> [GitLabReferenceQuery] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { self.lineScopedRepositoryIssueQueries(inLine: String($0), minimumBareDigits: minimumBareDigits) }
    }

    static func lineScopedRepositoryIssueQueries(inLine line: String, minimumBareDigits: Int) -> [GitLabReferenceQuery] {
        self.lineScopedRepositoryIssueNumberTokenMatches(inLine: line, minimumBareDigits: minimumBareDigits).map(\.query)
    }

    static func lineScopedRepositoryIssueNumberTokenMatches(
        inLine line: String,
        minimumBareDigits: Int
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        self.lineScopedSentenceFragments(in: line).flatMap {
            self.lineScopedRepositoryIssueNumberTokenMatches(inSentence: $0, minimumBareDigits: minimumBareDigits)
        }
    }

    static func lineScopedSentenceFragments(in line: String) -> [String] {
        line.split { character in
            character.isWhitespace
        }
        .reduce(into: [String]()) { fragments, token in
            if fragments.isEmpty {
                fragments.append(String(token))
            } else {
                fragments[fragments.count - 1] += " \(token)"
            }
            if self.endsLineScopedSentenceToken(token) {
                fragments.append("")
            }
        }
        .filter { $0.isEmpty == false }
    }

    private static func endsLineScopedSentenceToken(_ rawToken: Substring) -> Bool {
        var token = String(rawToken)
        while let last = token.last, self.isClosingSentenceDelimiter(last) {
            token.removeLast()
        }
        guard let last = token.last else { return false }

        return last == "." || last == "!" || last == "?" || last == ";"
    }

    private static func isClosingSentenceDelimiter(_ character: Character) -> Bool {
        switch character {
        case ")", "]", "}", "\"", "'", "”", "’":
            true
        default:
            false
        }
    }

    private static func lineScopedRepositoryIssueNumberTokenMatches(
        inSentence sentence: String,
        minimumBareDigits: Int
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        let tokens = self.referenceTokens(in: sentence)
        guard tokens.count >= 2 else { return [] }

        var matches: [GitLabReferenceIssueNumberTokenMatch] = []
        for index in tokens.indices.dropLast() {
            let repositoryFullName = tokens[index]
            guard self.isRepositoryFullName(repositoryFullName),
                  let issueMatches = self.lineScopedIssueNumberMatches(
                      afterRepositoryAt: index,
                      in: tokens,
                      minimumBareDigits: minimumBareDigits,
                      allowBareFirstNumber: true
                  )
            else { continue }

            matches.append(contentsOf: issueMatches.compactMap { match in
                guard let number = self.issueNumber(fromQuery: match.query) else { return nil }

                return GitLabReferenceIssueNumberTokenMatch(
                    query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number),
                    tokenIndex: match.tokenIndex
                )
            })
        }
        return matches
    }

    private static func lineScopedIssueNumberMatches(
        afterRepositoryAt repositoryIndex: Int,
        in tokens: [String],
        minimumBareDigits: Int,
        allowBareFirstNumber: Bool
    ) -> [GitLabReferenceIssueNumberTokenMatch]? {
        var index = tokens.index(after: repositoryIndex)
        if self.issueNumber(from: tokens[index], minimumBareDigits: 1, allowBareNumber: false) != nil {
            return self.bareIssueSeriesMatches(
                in: Array(tokens[index...]),
                minimumBareDigits: minimumBareDigits,
                tokenOffset: index
            )
        }

        let referenceKind = tokens[index].lowercased()
        guard self.isIssueReferenceFirstKindToken(referenceKind) else { return nil }

        index = tokens.index(after: index)
        if self.needsRequestContinuation(referenceKind),
           index < tokens.endIndex,
           self.isRequestContinuationToken(tokens[index])
        {
            index = tokens.index(after: index)
        }
        guard index < tokens.endIndex else { return nil }
        guard self.issueNumber(from: tokens[index], minimumBareDigits: 1, allowBareNumber: false) != nil else {
            guard allowBareFirstNumber,
                  tokens[index].allSatisfy(\.isNumber)
            else { return nil }

            let matches = self.bareIssueSeriesMatches(
                in: Array(tokens[index...]),
                minimumBareDigits: minimumBareDigits,
                tokenOffset: index
            )
            return matches.isEmpty ? nil : matches
        }

        let matches = self.repeatedLineScopedIssueNumberMatches(
            startingAt: index,
            in: tokens,
            minimumBareDigits: minimumBareDigits
        )
        return matches.isEmpty ? nil : matches
    }

    private static func repeatedLineScopedIssueNumberMatches(
        startingAt firstIssueIndex: Int,
        in tokens: [String],
        minimumBareDigits: Int
    ) -> [GitLabReferenceIssueNumberTokenMatch] {
        var matches: [GitLabReferenceIssueNumberTokenMatch] = []
        var index = firstIssueIndex
        while index < tokens.endIndex {
            if self.isRepositoryFullName(tokens[index]) {
                break
            }

            let token = tokens[index].lowercased()
            let seriesStartIndex: Int?
            if self.issueNumber(from: tokens[index], minimumBareDigits: 1, allowBareNumber: false) != nil {
                seriesStartIndex = index
            } else if self.isIssueReferenceFirstKindToken(token) {
                var nextIndex = tokens.index(after: index)
                if self.needsRequestContinuation(token),
                   nextIndex < tokens.endIndex,
                   self.isRequestContinuationToken(tokens[nextIndex])
                {
                    nextIndex = tokens.index(after: nextIndex)
                }
                seriesStartIndex = nextIndex < tokens.endIndex ? nextIndex : nil
            } else {
                seriesStartIndex = nil
            }

            guard let seriesStartIndex else {
                index = tokens.index(after: index)
                continue
            }

            let seriesMatches = self.bareIssueSeriesMatches(
                in: Array(tokens[seriesStartIndex...]),
                minimumBareDigits: minimumBareDigits,
                tokenOffset: seriesStartIndex
            )
            guard seriesMatches.isEmpty == false else {
                index = tokens.index(after: index)
                continue
            }

            matches.append(contentsOf: seriesMatches)
            index = seriesMatches.last.map { tokens.index(after: $0.tokenIndex) } ?? tokens.index(after: index)
        }

        return matches
    }

    private static func isIssueReferenceFirstKindToken(_ token: String) -> Bool {
        switch token.lowercased() {
        case "mr", "mrs", "merge", "merge-request", "merge-requests", "mergerequest", "mergerequests",
             "pr", "prs", "pull", "pull-request", "pull-requests", "pullrequest", "pullrequests",
             "issue", "issues":
            true
        default:
            false
        }
    }

    private static func needsRequestContinuation(_ token: String) -> Bool {
        ["merge", "pull"].contains(token.lowercased())
    }

    private static func isRequestContinuationToken(_ token: String) -> Bool {
        ["request", "requests"].contains(token.lowercased())
    }
}
