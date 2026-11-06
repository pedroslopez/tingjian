import Foundation

/// Hanzi → pinyin with tone marks, via the system's Mandarin-Latin transform.
public enum Pinyin {
    public static func romanize(_ text: String) -> String {
        guard var latin = text.applyingTransform(.mandarinToLatin, reverse: false) else { return text }
        latin = latin.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? latin
        // "wēn20dù" → "wēn 20 dù"
        latin = latin.replacingOccurrences(of: #"(?<=[^\s\d])(?=\d)"#, with: " ", options: .regularExpression)
        latin = latin.replacingOccurrences(of: #"(?<=\d)(?=[^\s\d,.!?;:%])"#, with: " ", options: .regularExpression)
        latin = latin.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return latin.prefix(1).uppercased() + latin.dropFirst()
    }
}
