import AppKit
import RepoPeekCore

extension StatusBarMenuManager {
    func fallbackStatusImage() -> NSImage {
        RepoPeekStatusIconRenderer.makeIcon(
            for: RepoPeekStatusIconKind.resolve(session: self.appState.session),
            expressionVariant: self.statusIconExpressionVariant,
            direction: self.statusIconDirection
        )
    }

    func syncStatusIconAnimation(for kind: RepoPeekStatusIconKind) {
        if self.statusIconAnimationKind != kind {
            self.statusIconAnimationKind = kind
            self.statusIconAnimationFrame = 0
            self.statusIconExpressionVariant = kind.randomExpressionVariant()
            self.statusIconDirection = RepoPeekStatusIconDirection.random()
            self.statusIconActiveDirectionTicksRemaining = Self.randomStatusIconActiveDirectionTicks()
        }

        let interval = self.statusIconAnimationInterval(for: kind)
        guard self.statusIconAnimationTimer == nil || self.statusIconAnimationTimerInterval != interval else { return }

        self.statusIconAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStatusIconAnimation()
            }
        }
        self.statusIconAnimationTimer = timer
        self.statusIconAnimationTimerInterval = interval
        RunLoop.main.add(timer, forMode: .common)
    }

    func statusIconAnimationInterval(for kind: RepoPeekStatusIconKind) -> TimeInterval {
        guard kind != .running else {
            return Self.statusIconRunningAnimationInterval
        }

        let interval = AppearanceSettings.clampedStatusIconExpressionIntervalSeconds(
            self.appState.session.settings.appearance.statusIconExpressionIntervalSeconds
        )
        return TimeInterval(interval)
    }

    func advanceStatusIconAnimation() {
        guard let kind = self.statusIconAnimationKind,
              let button = self.statusItem?.button
        else {
            self.stopStatusIconAnimation()
            return
        }

        if kind == .running {
            self.advanceStatusIconRunningFrame(for: button)
            return
        }

        self.advanceStatusIconIdleFrame(for: button)
    }

    func stopStatusIconAnimation() {
        self.statusIconAnimationTimer?.invalidate()
        self.statusIconAnimationTimer = nil
        self.statusIconAnimationTimerInterval = nil
        self.statusIconAnimationKind = nil
        self.statusIconAnimationFrame = 0
        self.statusIconExpressionVariant = RepoPeekStatusIconKind.standing.randomExpressionVariant()
        self.statusIconDirection = RepoPeekStatusIconDirection.random()
        self.statusIconActiveDirectionTicksRemaining = Self.randomStatusIconActiveDirectionTicks()
    }

    func advanceStatusIconIdleFrame(for button: NSStatusBarButton) {
        let idleKind = self.statusIconAnimationKind ?? .standing
        self.statusIconExpressionVariant = idleKind.randomExpressionVariant(excluding: self.statusIconExpressionVariant)
        self.statusIconDirection = RepoPeekStatusIconDirection.random()

        self.setButtonImage(
            RepoPeekStatusIconRenderer.makeIcon(
                for: idleKind,
                expressionVariant: self.statusIconExpressionVariant,
                direction: self.statusIconDirection
            ),
            for: button
        )
    }

    func advanceStatusIconRunningFrame(for button: NSStatusBarButton) {
        let running = RepoPeekStatusIconKind.running
        self.advanceStatusIconDirectionIfNeeded()
        self.statusIconAnimationFrame = (self.statusIconAnimationFrame + 1) % running.animationFrameCount
        self.setButtonImage(
            RepoPeekStatusIconRenderer.makeIcon(
                for: running,
                frame: self.statusIconAnimationFrame,
                direction: self.statusIconDirection
            ),
            for: button
        )
    }

    func advanceStatusIconDirectionIfNeeded() {
        guard self.statusIconAnimationKind == .running else { return }

        self.statusIconActiveDirectionTicksRemaining -= 1
        guard self.statusIconActiveDirectionTicksRemaining <= 0 else { return }

        self.statusIconDirection = self.statusIconDirection.opposite
        self.statusIconActiveDirectionTicksRemaining = Self.randomStatusIconActiveDirectionTicks()
    }

    func displayStatusIconKind(for statusKind: RepoPeekStatusIconKind) -> RepoPeekStatusIconKind {
        statusKind
    }

    static func randomStatusIconActiveDirectionTicks() -> Int {
        Int.random(in: self.statusIconActiveDirectionTickRange)
    }
}
