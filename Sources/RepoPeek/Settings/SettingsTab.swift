import Foundation
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case shortcuts
    case display
    case repositories
    case accounts
    case notifications
    case advanced
    case about
    #if DEBUG
        case debug
    #endif

    static let windowWidth: CGFloat = 800
    static let windowHeight: CGFloat = 770
}
