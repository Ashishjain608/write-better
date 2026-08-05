import Foundation

/// The one-tap rewrites offered above the custom-prompt field.
///
/// The UI renders `QuickAction.allCases` generically — adding a case here is the
/// only change needed to add a button.
nonisolated enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    /// Spelling, grammar and punctuation only — wording and voice untouched.
    case proofread
    /// Same content, read more clearly.
    case clarify
    /// Same content, fewer words.
    case concise
    /// Workplace-appropriate register.
    case professional
    /// Warmer, more conversational register.
    case friendly

    var id: String { rawValue }

    /// Button label.
    var title: String {
        switch self {
        case .proofread: return "Fix Grammar"
        case .clarify: return "Clarify"
        case .concise: return "Shorten"
        case .professional: return "Professional"
        case .friendly: return "Friendly"
        }
    }

    /// SF Symbol shown on the button.
    var icon: String {
        switch self {
        case .proofread: return "text.badge.checkmark"
        case .clarify: return "wand.and.stars"
        case .concise: return "scissors"
        case .professional: return "briefcase.fill"
        case .friendly: return "face.smiling"
        }
    }

    /// The instruction handed to the model. Written as a direct order so it reads
    /// well after "Instruction: " in `ImprovementRequest.userPrompt`.
    var instruction: String {
        switch self {
        case .proofread:
            return """
            Correct spelling, grammar, punctuation and capitalisation errors only. \
            Keep the author's exact wording, vocabulary, tone and sentence structure \
            wherever it is already correct. Do not rephrase, reorder, shorten or \
            expand anything. If the text has no errors, return it unchanged.
            """
        case .clarify:
            return """
            Rewrite for clarity and flow. Remove ambiguity, tighten awkward phrasing \
            and fix any errors, while keeping every fact, claim and detail intact. \
            Keep roughly the same length and the same level of formality.
            """
        case .concise:
            return """
            Rewrite to be shorter and tighter. Cut filler, hedging and repetition, \
            but keep every fact, request and commitment. Do not drop information to \
            save words, and do not turn prose into bullet points.
            """
        case .professional:
            return """
            Rewrite in a polished, professional register suitable for work email or \
            a business document. Remove slang and casual filler, keep it warm rather \
            than stiff, and do not add corporate jargon or padding.
            """
        case .friendly:
            return """
            Rewrite in a warmer, more conversational register, as if writing to a \
            colleague you get on with. Keep it natural rather than gushing, and do \
            not add emoji, exclamation marks or pleasantries that were not implied.
            """
        }
    }
}
