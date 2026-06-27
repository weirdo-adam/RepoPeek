import AppKit
@testable import RepoPeek
import RepoPeekCore
import Testing

struct RepoPeekStatusIconTests {
    @Test
    func `refreshing resolves to running pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: true,
            isLocalScanning: false,
            lastError: "No internet connection.",
            repositories: [Self.repository(ciStatus: .failing, openPulls: 4)]
        )

        #expect(kind == .running)
    }

    @Test
    func `network errors resolve to crouching pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: false,
            isLocalScanning: false,
            lastError: "No internet connection.",
            repositories: [Self.repository(ciStatus: .failing, openPulls: 4)]
        )

        #expect(kind == .crouching)
    }

    @Test
    func `pipeline failures resolve to looking pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: false,
            isLocalScanning: false,
            lastError: nil,
            repositories: [Self.repository(ciStatus: .failing, openPulls: 4)]
        )

        #expect(kind == .looking)
    }

    @Test
    func `open merge requests resolve to looking pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: false,
            isLocalScanning: false,
            lastError: nil,
            repositories: [
                Self.repository(openPulls: 2),
                Self.repository(openPulls: 3)
            ]
        )

        #expect(kind == .looking)
    }

    @Test
    func `quiet repositories resolve to standing pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: false,
            isLocalScanning: false,
            lastError: nil,
            repositories: [Self.repository()]
        )

        #expect(kind == .standing)
    }

    @Test
    func `rate limited messages do not resolve to crouching pose`() {
        let kind = RepoPeekStatusIconKind.resolve(
            isRefreshing: false,
            isLocalScanning: false,
            lastError: "Rate limited; retry soon.",
            repositories: []
        )

        #expect(kind == .standing)
    }

    @MainActor
    @Test
    func `status renderer produces menu bar sized resource images`() {
        for kind in [
            RepoPeekStatusIconKind.standing,
            .running,
            .crouching,
            .looking
        ] {
            let image = RepoPeekStatusIconRenderer.makeIcon(for: kind)

            #expect(image.size == NSSize(width: 20, height: 20))
            #expect(!image.isTemplate)
        }
    }

    @Test
    func `running pose exposes multiple animation frames`() {
        #expect(RepoPeekStatusIconKind.running.animationFrameCount == 4)
        #expect(RepoPeekStatusIconKind.standing.animationFrameCount == 1)
        #expect(RepoPeekStatusIconKind.running.normalizedAnimationFrame(5) == 1)
        #expect(RepoPeekStatusIconKind.running.normalizedAnimationFrame(-1) == 3)
    }

    @Test
    func `idle poses expose randomized expression variants`() {
        #expect(RepoPeekStatusIconKind.standing.expressionVariantCount == 3)
        #expect(RepoPeekStatusIconKind.looking.expressionVariantCount == 2)
        #expect(RepoPeekStatusIconKind.crouching.expressionVariantCount == 2)
        #expect(RepoPeekStatusIconKind.running.expressionVariantCount == 1)
        #expect(RepoPeekStatusIconKind.standing.normalizedExpressionVariant(4) == 1)
        #expect(RepoPeekStatusIconKind.looking.normalizedExpressionVariant(-1) == 1)
        #expect(RepoPeekStatusIconKind.running.normalizedExpressionVariant(4) == 0)
        #expect(RepoPeekStatusIconKind.looking.randomExpressionVariant(excluding: 0) == 1)
        #expect(RepoPeekStatusIconKind.running.randomExpressionVariant(excluding: 4) == 0)
    }

    @MainActor
    @Test
    func `idle expression animation uses configured seconds`() {
        let appState = AppState()
        appState.session.settings.appearance.statusIconExpressionIntervalSeconds = 7
        let manager = StatusBarMenuManager(appState: appState)

        #expect(manager.statusIconAnimationIntervalForTesting(kind: .standing) == 7)
        #expect(manager.statusIconAnimationIntervalForTesting(kind: .looking) == 7)
        #expect(manager.statusIconAnimationIntervalForTesting(kind: .crouching) == 7)
        #expect(manager.statusIconAnimationIntervalForTesting(kind: .running) == 0.10)
    }

    @MainActor
    @Test
    func `running animation frames are cached independently`() {
        let firstFrame = RepoPeekStatusIconRenderer.makeIcon(for: .running, frame: 0)
        let secondFrame = RepoPeekStatusIconRenderer.makeIcon(for: .running, frame: 1)
        let wrappedSecondFrame = RepoPeekStatusIconRenderer.makeIcon(for: .running, frame: 5)

        #expect(firstFrame !== secondFrame)
        #expect(secondFrame === wrappedSecondFrame)
        #expect(secondFrame.size == NSSize(width: 20, height: 20))
        #expect(!secondFrame.isTemplate)
    }

    @MainActor
    @Test
    func `expression variants are cached independently`() {
        let firstVariant = RepoPeekStatusIconRenderer.makeIcon(for: .standing, expressionVariant: 0)
        let secondVariant = RepoPeekStatusIconRenderer.makeIcon(for: .standing, expressionVariant: 1)
        let wrappedSecondVariant = RepoPeekStatusIconRenderer.makeIcon(for: .standing, expressionVariant: 4)

        #expect(firstVariant !== secondVariant)
        #expect(secondVariant === wrappedSecondVariant)
        #expect(secondVariant.size == NSSize(width: 20, height: 20))
        #expect(!secondVariant.isTemplate)
    }

    private static func repository(ciStatus: CIStatus = .unknown, openPulls: Int = 0) -> Repository {
        Repository(
            id: UUID().uuidString,
            name: "repo",
            owner: "example",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: ciStatus,
            openIssues: 0,
            openPulls: openPulls,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
