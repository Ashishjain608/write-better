# WriteBetter v1.0 — Shared Contract (authoritative)

Repo: `/Users/ashishjain/dev/write-better`
App sources: `WriteBetter/WriteBetter/`

All agents MUST obey this file. If something here conflicts with your own judgement,
follow this file — another agent is coding against it.

---

## 0. Hard global rules

- **Deployment target is macOS 14.0.** Do not use API newer than macOS 14 unconditionally.
  Newer eye-candy (e.g. macOS 26 Liquid Glass `.glassEffect`) is allowed ONLY behind
  `if #available(macOS 26.0, *)` with a working macOS 14 fallback.
- Swift 5, SwiftUI + AppKit. **Zero third-party dependencies.** No SPM packages.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`: any new `.swift` file
  placed under `WriteBetter/WriteBetter/` is compiled automatically. Do NOT edit
  `project.pbxproj` to register sources.
- No secrets in source. No `print()` of user text or API keys.
- Everything must compile with `xcodebuild -scheme WriteBetter -configuration Release`.

## 1. File ownership (STRICT — do not edit files you do not own)

| Agent | Owns (create/edit only these) |
|-------|-------------------------------|
| **P — Providers** | `WriteBetter/WriteBetter/Services/**`, `WriteBetter/WriteBetter/Models/**`, `WriteBetter/WriteBetter/Utils/**` |
| **U — UX** | `WriteBetter/WriteBetter/Views/**`, `WriteBetter/WriteBetter/Managers/**`, `WriteBetter/WriteBetter/WriteBetterApp.swift` |
| **D — Packaging** | `WriteBetter/WriteBetter.xcodeproj/project.pbxproj`, `WriteBetter/WriteBetter/Info.plist`, `WriteBetter/WriteBetter/WriteBetter.entitlements`, `WriteBetter/WriteBetter/Assets.xcassets/**`, `WriteBetter/ExportOptions.plist`, `scripts/**`, `create-dmg.sh`, `Installer/**`, `README.md`, `SETUP.md`, `.gitignore` |

Nobody edits another agent's files. Nobody runs `git commit`, `git add`, `git checkout`,
`git stash`, or `git restore`. The orchestrator integrates.

## 2. Public API contract (P implements, U consumes)

P MUST provide exactly these symbols. U MUST code against exactly these symbols.

```swift
// Utils/AIProvider.swift
enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic, openai, gemini
    var id: String { rawValue }
    var displayName: String     // "Anthropic", "OpenAI", "Google Gemini"
    var modelFamilyName: String // "Claude", "GPT", "Gemini"
    var iconSymbol: String      // SF Symbol name, always renderable
    var accent: Color           // SwiftUI Color, brand accent for this provider
    var keyPlaceholder: String  // e.g. "sk-ant-api03-…"
    var keyPrefixHint: String?  // e.g. "sk-ant-" — nil if provider has no stable prefix
    var consoleURL: URL         // where the user gets a key
    var models: [AIModelOption] // ordered; index 0 is the default
}

struct AIModelOption: Identifiable, Hashable, Sendable {
    let id: String      // exact API model id
    let name: String    // human name, e.g. "Claude Sonnet 4.5"
    let blurb: String   // one short line, e.g. "Best quality"
}

// Models/QuickAction.swift
enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    // P decides the exact case list (5–6 max). U renders QuickAction.allCases generically
    // and must not hardcode the case names or the count.
    var id: String { rawValue }
    var title: String       // button label
    var icon: String        // SF Symbol
    var instruction: String // prompt fragment
}

// Models/ImprovementRequest.swift
struct ImprovementRequest: Sendable {
    let originalText: String
    let action: QuickAction?
    let customPrompt: String?
    var systemPrompt: String { get }
    var userPrompt: String { get }
}

// Services/AIService.swift
protocol AIService: Sendable {
    var provider: AIProvider { get }
    var modelID: String { get }
    func improveTextStream(request: ImprovementRequest) -> AsyncThrowingStream<String, Error>
    func validateKey() async -> Result<Void, AIServiceError>   // cheap 1-token ping
}

enum AIServiceError: LocalizedError, Sendable {
    case noProviderConfigured          // no provider has a key at all
    case missingKey(AIProvider)
    case invalidKey(AIProvider)        // 401/403
    case rateLimited(retryAfter: TimeInterval?)   // 429
    case quotaExceeded                 // billing/credit exhausted
    case serverError(Int)              // 5xx
    case timedOut
    case offline
    case network(String)
    case api(String)
    case invalidResponse
    case emptyInput
    // errorDescription: one short user-facing sentence
    // recoverySuggestion: one short actionable line (U renders it under the error)
}

// Services/AIServiceFactory.swift
enum AIServiceFactory {
    /// Service for the currently-selected provider + model, using the stored key.
    /// Throws .noProviderConfigured / .missingKey when unusable.
    @MainActor static func makeService() throws -> AIService
    /// Ad-hoc service, used by Settings' "Test key" button before the key is saved.
    static func service(for provider: AIProvider, apiKey: String, modelID: String) -> AIService
}

// Utils/SettingsStore.swift  — the single source of truth for user settings
@MainActor final class SettingsStore: ObservableObject {
    static let shared: SettingsStore

    @Published var selectedProvider: AIProvider          // persisted
    @Published private(set) var configuredProviders: Set<AIProvider>  // providers holding a key

    func apiKey(for provider: AIProvider) -> String      // "" when unset
    func setAPIKey(_ key: String, for provider: AIProvider)   // "" deletes; Keychain-backed
    func hasKey(for provider: AIProvider) -> Bool

    func modelID(for provider: AIProvider) -> String     // persisted, defaults to models[0].id
    func setModelID(_ id: String, for provider: AIProvider)

    var isConfigured: Bool                               // selected provider has a usable key

    // UI preferences owned by U's screens but persisted here (P implements storage only):
    @Published var autoCaptureSelection: Bool            // default false
    @Published var launchAtLogin: Bool                   // default false; P persists the flag,
                                                         // U performs SMAppService registration
}
```

**Keychain**: API keys live in the macOS Keychain (`kSecClassGenericPassword`,
service `com.aj.WriteBetter.apikeys`, account = provider rawValue), NOT UserDefaults.
On first run, migrate an existing `ANTHROPIC_API_KEY` from `UserDefaults.standard`
into the Keychain and remove the UserDefaults entry.

## 3. Behaviour contract

- Streaming is the only path. Every provider streams incrementally (SSE for Anthropic
  and OpenAI, `streamGenerateContent?alt=sse` for Gemini).
- Requests must be cancellable: cancelling the consuming `Task` must abort the URLSession
  work promptly.
- Request timeout: 60s overall, 20s to first byte.
- On any non-2xx, map to the precise `AIServiceError` case above — never a bare string.

## 4. Design system (single source of truth: `scratchpad/DESIGN-BRIEF.md`)

Agent R1 writes `DESIGN-BRIEF.md`. Agents U and D both consume it, so the app UI, the
app icon, and the DMG background all share one identity (palette, corner radii,
typography, motion, logo mark). U owns the SwiftUI `Theme`; D owns the raster assets.
If they disagree, `DESIGN-BRIEF.md` wins.

## 5. Verification each agent owes

- **P**: a `#if DEBUG` self-check that builds requests for all 3 providers and asserts the
  URL/headers/body shape, plus SSE-chunk parsing asserts for all 3 wire formats using
  captured sample payloads. No network in the check.
- **U**: the app must build and every screen must have a working SwiftUI `#Preview`.
- **D**: `./create-dmg.sh` must run end-to-end on this machine and produce a mountable DMG.

Report back: files touched, the exact public symbols you added, anything you could not do.
