# WriteBetter

A native macOS utility that improves your text using AI. Select any text, press `Cmd+Shift+Space`, and get instant AI-powered text improvements.

## Features

- **System-wide text improvement** - Works in any macOS application
- **Quick actions** - Professional, Friendly, Concise, or Detailed presets
- **Custom prompts** - Fine-tune improvements with your own instructions
- **Powered by Claude** - Uses Anthropic's Claude API for high-quality results
- **Native macOS app** - Built with Swift & SwiftUI for optimal performance
- **Cursor-positioned popup** - Appears right where you're working

## How to Use

1. Select any text in any application
2. Press `Cmd+Shift+Space`
3. Review the improved text
4. Use quick actions or custom prompts to refine
5. Click "Copy & Close" to use the improved text

## Setup Instructions

### 1. Prerequisites

- macOS 12.0 or later
- Xcode 14.0 or later
- Anthropic API key ([Get one here](https://console.anthropic.com/))

### 2. Configure API Key

Add your Anthropic API key to the `.env` file:

```bash
ANTHROPIC_API_KEY=sk-ant-your-api-key-here
```

### 3. Open in Xcode

```bash
cd WriteBetter
open WriteBetter.xcodeproj
```

If the `.xcodeproj` file doesn't exist yet, create a new macOS App project in Xcode:

1. Open Xcode
2. File → New → Project
3. Choose "macOS" → "App"
4. Product Name: `WriteBetter`
5. Interface: `SwiftUI`
6. Language: `Swift`
7. Save in the `WriteBetter` directory

Then add all the source files from the `WriteBetter` folder to your project.

### 4. Configure Project Settings

In Xcode, configure the following:

**Target Settings:**
- Deployment Target: macOS 12.0 or later
- Bundle Identifier: `com.yourname.WriteBetter`

**Signing & Capabilities:**
- Enable "Disable Library Validation" (required for hotkey registration)
- Add `WriteBetter.entitlements` file
- Configure signing certificate

**Build Settings:**
- Set "Enable Hardened Runtime" to YES
- Add `Info.plist` to the target

### 5. Grant Permissions

On first launch, the app will request:
- **Accessibility permissions** - Required to capture selected text
- Grant these in System Preferences → Security & Privacy → Privacy → Accessibility

### 6. Build and Run

1. Select your Mac as the build target
2. Press `Cmd+R` to build and run
3. The app icon will appear in your menu bar
4. Click the icon to access Settings and add your API key

## Project Structure

```
WriteBetter/
├── WriteBetterApp.swift          # Main app entry point & menu bar setup
├── Managers/
│   ├── HotkeyManager.swift       # Global hotkey registration
│   ├── TextExtractor.swift       # Text selection capture
│   └── ConfigManager.swift       # Settings & API key management
├── Services/
│   ├── AIService.swift           # AI service protocol
│   └── ClaudeService.swift       # Anthropic Claude API integration
├── Views/
│   ├── PopupWindow.swift         # Floating window controller
│   ├── ImprovementView.swift    # Main improvement UI
│   └── SettingsView.swift        # Settings panel
├── Models/
│   ├── ImprovementRequest.swift  # Request data model
│   └── QuickAction.swift         # Quick action types
└── Utils/
    └── Constants.swift           # App constants & API key loading
```

## Architecture

The app follows a clean architecture with clear separation of concerns:

- **AIService Protocol** - Abstraction layer for AI providers (easy to add GPT, Gemini, etc.)
- **ClaudeService** - Current implementation using Anthropic's API
- **HotkeyManager** - Carbon-based global hotkey registration
- **TextExtractor** - Accessibility API for text capture
- **PopupWindow** - Floating NSPanel positioned at cursor

## Extending the App

### Adding a New AI Provider

1. Create a new service conforming to `AIService` protocol
2. Implement the `improveText(request:)` method
3. Update settings to allow provider selection

Example:

```swift
class OpenAIService: AIService {
    func improveText(request: ImprovementRequest) async throws -> String {
        // Implement OpenAI API call
    }
}
```

### Adding New Quick Actions

Edit `Models/QuickAction.swift`:

```swift
enum QuickAction: String, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case detailed = "Detailed"
    case creative = "Creative"  // Add new action

    var description: String {
        switch self {
        case .creative:
            return "more creative and engaging"
        // ...
        }
    }
}
```

## Troubleshooting

**Hotkey not working:**
- Check Accessibility permissions in System Preferences
- Restart the app after granting permissions

**API errors:**
- Verify your API key in Settings
- Check internet connection
- Ensure API key has sufficient credits

**Window not appearing:**
- Check if text was selected before pressing hotkey
- Try clicking in a different application first

## Privacy

- No text is stored or logged
- All API calls go directly to Anthropic
- API key stored in macOS UserDefaults (or .env during development)

## License

This is a hobby project for personal use.

## Credits

Built with:
- Swift & SwiftUI
- Anthropic Claude API
- Carbon framework for hotkey registration
