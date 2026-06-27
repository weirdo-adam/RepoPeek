@testable import RepoPeek
import RepoPeekCore
import SwiftUI
import Testing

struct MenuItemHostingTests {
    @Test
    func `repo menu stats keep primary counts and hide zero secondary counts`() {
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "group",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo)

        let stats = RepoMenuCardView.visibleStats(from: display.stats)

        #expect(stats.map(\.id) == ["issues", "mrs"])
    }

    @MainActor
    @Test
    func `measured height clamps non finite SwiftUI layouts`() {
        let view = MenuItemHostingView(rootView: AnyView(Color.clear.frame(maxHeight: .infinity)))

        let height = view.measuredHeight(width: 360)

        #expect(height.isFinite)
        #expect(height > 0)
        #expect(height <= 360)
    }

    @MainActor
    @Test
    func `zero height SwiftUI rows use fallback height`() {
        let view = MenuItemHostingView(rootView: AnyView(EmptyView()))

        #expect(view.measuredHeight(width: 320) > 0)
    }

    @MainActor
    @Test
    func `plain menu items measure geometry content at intrinsic height`() throws {
        let item = MenuItemViewFactory().makeItem(for: FirstOpenHeaderProbe(), enabled: false)
        let view = try #require(item.view as? MenuItemHostingView)

        let height = view.measuredHeight(width: 360)

        #expect(height.isFinite)
        #expect(height >= 70)
        #expect(height < 120)
    }
}

private struct FirstOpenHeaderProbe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("example · Contributions · 12 months")
                .font(.caption.weight(.semibold))
            GeometryReader { _ in
                Color.clear
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            HStack {
                Text("Apr 2025")
                Spacer()
                Text("May 2026")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
