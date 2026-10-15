import Foundation

enum L10n {
    static var chinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static func t(_ zh: String, _ en: String) -> String {
        chinese ? zh : en
    }
}
