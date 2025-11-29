import Foundation

struct ImprovementRequest {
    let originalText: String
    let action: QuickAction?
    let customPrompt: String?

    func buildPrompt() -> String {
        var prompt = "Improve the following text"

        if let action = action {
            prompt += " to make it \(action.description)"
        } else if let customPrompt = customPrompt, !customPrompt.isEmpty {
            prompt += " with this instruction: \(customPrompt)"
        } else {
            prompt += " to make it better, crisp and well formatted"
        }

        prompt += ". Only return the improved text without any explanations or additional commentary.\n\nText to improve:\n\(originalText)"

        return prompt
    }
}
