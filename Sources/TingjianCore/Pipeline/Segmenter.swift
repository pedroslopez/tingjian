import Foundation

/// Splits recognizer text into subtitle-sized sentences.
public enum Segmenter {
    static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…"]
    static let closers: Set<Character> = ["”", "’", "」", "』", "）", ")", "\"", "'"]
    static let commas: Set<Character> = ["，", ",", "、", "："]

    /// Removes the spaces the recognizer puts around CJK text ("气温 20度 ，" → "气温20度，").
    public static func normalize(_ text: String) -> String {
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var out = ""
        out.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() {
            if c.isWhitespace {
                let prev = i > 0 ? chars[i - 1] : nil
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if prev.map(isCJK) == true || next.map(isCJK) == true || prev?.isWhitespace == true { continue }
            }
            out.append(c)
        }
        return out
    }

    /// Sentences, each ending in a terminator except possibly the last.
    /// Sentences longer than `softLimit` characters are split after a comma.
    public static func sentences(_ text: String, softLimit: Int = 36) -> [String] {
        let text = normalize(text)
        var result: [String] = []
        var current = ""
        var chars = text.makeIterator()
        var pending: Character? = chars.next()
        while let c = pending {
            current.append(c)
            pending = chars.next()
            // A Latin full stop ends a sentence only before a space or the end,
            // so "3.5" and "U.S.A" stay intact.
            let isFullStop = c == "." && (pending == nil || pending!.isWhitespace)
            if terminators.contains(c) || isFullStop {
                // Keep runs like "？！" and closing quotes with the sentence.
                while let p = pending, terminators.contains(p) || closers.contains(p) {
                    current.append(p)
                    pending = chars.next()
                }
                result.append(contentsOf: softSplit(current.trimmingCharacters(in: .whitespaces), limit: softLimit))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(contentsOf: softSplit(tail, limit: softLimit)) }
        return result.filter { !$0.allSatisfy { $0.isWhitespace || terminators.contains($0) || $0 == "." } }
    }

    private static func softSplit(_ sentence: String, limit: Int) -> [String] {
        var rest = Substring(sentence)
        var parts: [String] = []
        while rest.count > limit {
            // Last comma within the limit, but not too early.
            let window = rest.prefix(limit)
            guard let cut = window.lastIndex(where: commas.contains),
                  rest.distance(from: rest.startIndex, to: cut) >= limit / 3 else { break }
            parts.append(String(rest[...cut]))
            rest = rest[rest.index(after: cut)...].drop(while: \.isWhitespace)
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            switch s.value {
            case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }
}
