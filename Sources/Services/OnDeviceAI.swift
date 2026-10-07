import Foundation
import FoundationModels

/// Apple's on-device language model (iOS 26 on Apple Intelligence iPhones). Prompts
/// and replies never leave the phone. Every caller keeps a rules-only fallback,
/// because the model is missing on older phones, may still be downloading, and can
/// refuse a prompt.
///
/// FoundationModels is weak-linked in project.yml, so nothing here may touch its
/// types outside an `#available(iOS 26.0, *)` check.
enum OnDeviceAI {
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// The model's reply, or nil when it is unavailable or the request fails.
    /// A fresh session per call keeps each request inside the small context window.
    /// A low temperature keeps labelling steady: the same text gets the same answer.
    static func respond(instructions: String, prompt: String, temperature: Double? = nil) async -> String? {
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: [], instructions: instructions)
            do {
                let options = GenerationOptions(sampling: nil, temperature: temperature, maximumResponseTokens: 400)
                let response = try await session.respond(to: prompt, options: options)
                return response.content
            } catch {
                return nil
            }
        }
        return nil
    }
}
