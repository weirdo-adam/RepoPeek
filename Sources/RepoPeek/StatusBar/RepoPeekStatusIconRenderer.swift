import AppKit
import RepoPeekCore

enum RepoPeekStatusIconKind: Hashable {
    case standing
    case running
    case crouching
    case looking

    var tooltip: String {
        switch self {
        case .standing:
            "Ready"
        case .running:
            "Syncing GitLab data"
        case .crouching:
            "GitLab is unavailable"
        case .looking:
            "Repository activity needs attention"
        }
    }

    var animationFrameCount: Int {
        switch self {
        case .running:
            4
        case .standing, .crouching, .looking:
            1
        }
    }

    var expressionVariantCount: Int {
        switch self {
        case .standing:
            3
        case .crouching, .looking:
            2
        case .running:
            1
        }
    }

    func normalizedAnimationFrame(_ frame: Int) -> Int {
        let count = self.animationFrameCount
        guard count > 1 else { return 0 }

        return ((frame % count) + count) % count
    }

    func normalizedExpressionVariant(_ variant: Int) -> Int {
        let count = self.expressionVariantCount
        guard count > 1 else { return 0 }

        return ((variant % count) + count) % count
    }

    func randomExpressionVariant() -> Int {
        Int.random(in: 0 ..< self.expressionVariantCount)
    }

    func randomExpressionVariant(excluding currentVariant: Int) -> Int {
        let count = self.expressionVariantCount
        guard count > 1 else { return 0 }

        let normalizedCurrent = self.normalizedExpressionVariant(currentVariant)
        let candidate = Int.random(in: 0 ..< count - 1)
        return candidate >= normalizedCurrent ? candidate + 1 : candidate
    }

    static func resolve(session: Session) -> RepoPeekStatusIconKind {
        self.resolve(
            isRefreshing: session.isRefreshingRepositories,
            isLocalScanning: session.localProjectsScanInProgress,
            lastError: session.lastError,
            repositories: session.repositories
        )
    }

    static func resolve(
        isRefreshing: Bool,
        isLocalScanning: Bool,
        lastError: String?,
        repositories: [Repository]
    ) -> RepoPeekStatusIconKind {
        if isRefreshing || isLocalScanning {
            return .running
        }

        if self.isOfflineError(lastError) {
            return .crouching
        }

        if repositories.contains(where: { $0.ciStatus == .failing }) {
            return .looking
        }

        let openMergeRequests = repositories.reduce(0) { $0 + max(0, $1.openPulls) }
        if openMergeRequests > 0 {
            return .looking
        }

        return .standing
    }

    private static func isOfflineError(_ error: String?) -> Bool {
        guard let error = error?.trimmingCharacters(in: .whitespacesAndNewlines),
              error.isEmpty == false
        else { return false }

        let normalized = error.lowercased()
        if normalized.contains("authentication") || normalized.contains("rate limited") {
            return false
        }

        return [
            "no internet",
            "timed out",
            "network",
            "offline",
            "unavailable",
            "could not connect",
            "cannot connect",
            "gitlab returned an unexpected response",
            "certificate"
        ].contains { normalized.contains($0) }
    }
}

enum RepoPeekStatusIconDirection: Hashable {
    case left
    case right

    var opposite: RepoPeekStatusIconDirection {
        switch self {
        case .left:
            .right
        case .right:
            .left
        }
    }

    static func random() -> RepoPeekStatusIconDirection {
        Bool.random() ? .right : .left
    }
}

@MainActor
enum RepoPeekStatusIconRenderer {
    private static let outputSize = NSSize(width: 20, height: 20)
    private static var cache: [IconCacheKey: NSImage] = [:]

    static func makeIcon(
        for kind: RepoPeekStatusIconKind,
        frame: Int = 0,
        expressionVariant: Int = 0,
        direction: RepoPeekStatusIconDirection = .right
    ) -> NSImage {
        let cacheKey = IconCacheKey(
            kind: kind,
            frame: kind.normalizedAnimationFrame(frame),
            expressionVariant: kind.normalizedExpressionVariant(expressionVariant),
            direction: direction
        )
        if let cached = self.cache[cacheKey] {
            return cached
        }

        let baseImage = self.makeResourceIcon(named: cacheKey.resourceName)
            ?? self.makeFallbackIcon(for: kind, frame: cacheKey.frame)
        let image = self.orientIcon(baseImage, direction: direction)
        self.cache[cacheKey] = image
        return image
    }

    private struct IconCacheKey: Hashable {
        let kind: RepoPeekStatusIconKind
        let frame: Int
        let expressionVariant: Int
        let direction: RepoPeekStatusIconDirection

        var resourceName: String {
            switch self.kind {
            case .running:
                "MenuBarIconRunning\(self.frame)"
            case .standing:
                "MenuBarIconStanding\(self.expressionVariant)"
            case .crouching:
                "MenuBarIconCrouching\(self.expressionVariant)"
            case .looking:
                "MenuBarIconLooking\(self.expressionVariant)"
            }
        }
    }

    private static func makeResourceIcon(named resourceName: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }

        image.size = self.outputSize
        image.isTemplate = false
        return image
    }

    private static func makeFallbackIcon(for kind: RepoPeekStatusIconKind, frame: Int) -> NSImage {
        let image = NSImage(size: self.outputSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: self.outputSize)).fill()
        NSColor.black.setFill()

        switch kind {
        case .running:
            self.drawFallbackRunning(frame: frame)
        case .standing, .crouching, .looking:
            self.drawFallbackStanding()
        }

        image.isTemplate = false
        return image
    }

    private static func orientIcon(_ image: NSImage, direction: RepoPeekStatusIconDirection) -> NSImage {
        guard direction == .left else { return image }

        let mirrored = NSImage(size: self.outputSize)
        mirrored.lockFocus()
        defer { mirrored.unlockFocus() }

        let transform = NSAffineTransform()
        transform.translateX(by: self.outputSize.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()
        image.draw(
            in: CGRect(origin: .zero, size: self.outputSize),
            from: CGRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        mirrored.isTemplate = image.isTemplate
        return mirrored
    }

    private static func drawFallbackStanding() {
        NSBezierPath(roundedRect: CGRect(x: 12.2, y: 2.0, width: 3.4, height: 13.4), xRadius: 1.7, yRadius: 1.7).fill()
        NSBezierPath(ovalIn: CGRect(x: 11.2, y: 13.0, width: 5.0, height: 3.3)).fill()
        self.strokeLine(from: CGPoint(x: 13.0, y: 3.4), to: CGPoint(x: 8.3, y: 1.8), width: 1.5)
        self.strokeLine(from: CGPoint(x: 14.8, y: 3.2), to: CGPoint(x: 17.4, y: 1.6), width: 1.4)
    }

    private static func drawFallbackRunning(frame: Int) {
        let offset: CGFloat = [0.0, 0.6, -0.1, 0.4][frame]
        NSBezierPath(ovalIn: CGRect(x: 7.2, y: 6.3 + offset, width: 11.2, height: 5.0)).fill()
        NSBezierPath(ovalIn: CGRect(x: 17.6, y: 8.3 + offset, width: 4.4, height: 3.1)).fill()
        self.strokeLine(from: CGPoint(x: 8.4, y: 8.3 + offset), to: CGPoint(x: 1.4, y: 7.0 + offset), width: 2.0)
        self.strokeLine(from: CGPoint(x: 10.2, y: 6.7 + offset), to: CGPoint(x: 7.2, y: 2.6), width: 1.6)
        self.strokeLine(from: CGPoint(x: 14.6, y: 6.5 + offset), to: CGPoint(x: 18.6, y: 2.9), width: 1.6)
    }

    private static func strokeLine(from start: NSPoint, to end: NSPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
    }
}
