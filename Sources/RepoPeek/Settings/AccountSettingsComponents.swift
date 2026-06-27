import RepoPeekCore
import SwiftUI

struct GitLabAccountRowView: View {
    let account: GitLabAccountSettings
    let username: String?
    let statusText: String
    let statusColor: Color
    let isChecking: Bool
    let spinnerSize: CGFloat
    let localize: (String) -> String
    let setEnabled: (Bool) -> Void
    let remove: () -> Void
    let checkToken: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                self.accountSummary
                self.statusLine
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            self.actions
        }
        .padding(.vertical, 4)
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.account.name)
                .font(.headline)
            Text(self.account.host.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let username, username.isEmpty == false {
                Text(username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if self.isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: self.spinnerSize, height: self.spinnerSize)
            }
            Text(self.statusText)
                .font(.caption)
                .foregroundStyle(self.statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Toggle(self.localize("Enabled"), isOn: Binding(
                get: { self.account.enabled },
                set: { self.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .help(self.localize("Enabled"))
            .accessibilityLabel(self.localize("Enabled"))

            Button(action: self.checkToken) {
                if self.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: self.spinnerSize, height: self.spinnerSize)
                } else {
                    Image(systemName: "checkmark.shield")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(self.isChecking)
            .frame(width: 28, height: 28)
            .help(self.localize("Check Token"))
            .accessibilityLabel(self.localize("Check Token"))

            Button(role: .destructive, action: self.remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .help(self.localize("Remove"))
            .accessibilityLabel(self.localize("Remove"))
        }
        .fixedSize()
    }
}

struct GitLabAccountFormView: View {
    @Binding var accountName: String
    @Binding var hostInput: String
    @Binding var patInput: String

    let isValidatingPAT: Bool
    let fieldMinWidth: CGFloat
    let spinnerSize: CGFloat
    let createTokenURL: URL
    let localize: (String) -> String
    let submit: () -> Void

    private let labelColumnWidth: CGFloat = 96
    private let rowHeight: CGFloat = 42
    private let rowSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.fieldRow(self.localize("Name")) {
                TextField("", text: self.$accountName, prompt: Text(self.localize("Work GitLab")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: self.fieldWidth)
            }
            self.rowDivider
            self.fieldRow(self.localize("Base URL")) {
                TextField("", text: self.$hostInput, prompt: Text("https://gitlab.example.com"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: self.fieldWidth)
            }
            self.rowDivider
            self.fieldRow(self.localize("Token")) {
                SecureField("", text: self.$patInput, prompt: Text("glpat-..."))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: self.fieldWidth)
            }
            self.rowDivider
            VStack(alignment: .leading, spacing: 10) {
                Text(self.localize("Required GitLab scopes: api, read_user, read_repository"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(self.localize("Create a token on GitLab"), destination: self.createTokenURL)
                    .font(.caption)
                HStack(spacing: 8) {
                    if self.isValidatingPAT {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: self.spinnerSize, height: self.spinnerSize)
                    }
                    Button(self.isValidatingPAT ? self.localize("Signing in...") : self.localize("Save Account")) {
                        self.submit()
                    }
                    .disabled(self.patInput.isEmpty || self.hostInput.isEmpty || self.isValidatingPAT)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)
            }
            .padding(.leading, self.inputLeadingPadding)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldWidth: CGFloat {
        max(self.fieldMinWidth, 360)
    }

    private var inputLeadingPadding: CGFloat {
        self.labelColumnWidth + self.rowSpacing
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, self.inputLeadingPadding)
    }

    private func fieldRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: self.rowSpacing) {
            Text(label)
                .frame(width: self.labelColumnWidth, alignment: .leading)
                .foregroundStyle(.primary)
            content()
            Spacer(minLength: 0)
        }
        .frame(height: self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
