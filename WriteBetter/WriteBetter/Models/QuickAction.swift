import Foundation

enum QuickAction: String, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case detailed = "Detailed"

    var description: String {
        switch self {
        case .professional:
            return "more professional and formal"
        case .friendly:
            return "more friendly and casual"
        case .concise:
            return "shorter and more concise"
        case .detailed:
            return "more detailed and comprehensive"
        }
    }

    var icon: String {
        switch self {
        case .professional:
            return "briefcase.fill"
        case .friendly:
            return "face.smiling"
        case .concise:
            return "text.alignleft"
        case .detailed:
            return "list.bullet.rectangle"
        }
    }
}
