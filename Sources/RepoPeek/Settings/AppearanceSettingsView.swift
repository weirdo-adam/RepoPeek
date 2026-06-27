import RepoPeekCore
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Picker(self.t("Card density"), selection: self.$session.settings.appearance.cardDensity) {
                ForEach(CardDensity.allCases, id: \.self) { density in
                    Text(self.t(density.label)).tag(density)
                }
            }
            .onChange(of: self.session.settings.appearance.cardDensity) { _, _ in self.appState.persistSettings() }

            Picker(self.t("Accent tone"), selection: self.$session.settings.appearance.accentTone) {
                ForEach(AccentTone.allCases, id: \.self) { tone in
                    Text(self.t(tone.label)).tag(tone)
                }
            }
            .onChange(of: self.session.settings.appearance.accentTone) { _, _ in self.appState.persistSettings() }

            Text(self.t("Contribution greens keep the classic contribution palette; System accent follows your macOS accent color."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
    }

    private func t(_ key: String) -> String {
        L10n.t(key, settings: self.session.settings)
    }
}
