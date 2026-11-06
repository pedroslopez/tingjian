import Foundation

public enum Languages {
    /// Locale handed to the speech transcriber.
    public static let speechLocale = Locale(identifier: "zh-CN")
    /// Translation source / target.
    public static let translationSource = Locale.Language(identifier: "zh-Hans")
    public static let translationTarget = Locale.Language(identifier: "en")
}
