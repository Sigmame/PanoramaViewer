import SwiftUI

extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
}

extension Text {
    func localized() -> Text {
        return Text(String(describing: self).localized())
    }
}

extension View {
    func localizedText(_ key: String) -> some View {
        self.accessibilityLabel(key.localized())
    }
} 