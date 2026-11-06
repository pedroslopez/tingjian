import Foundation

/// Chinese → English text translator. Implementations: Apple Translation (default);
/// a local MLX LLM (e.g. Qwen3) with rolling context could slot in here.
public protocol Translator: AnyObject, Sendable {
    /// Loads models so the first real request is fast.
    func prepare() async throws
    func translate(_ text: String) async throws -> String
}
