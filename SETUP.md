# Quick Setup Guide

Follow these steps to get WriteBetter running:

## Step 1: Add Your API Key

Edit the `.env` file and add your Anthropic API key:

```bash
ANTHROPIC_API_KEY=sk-ant-your-actual-api-key-here
```

Get your API key from: https://console.anthropic.com/

## Step 2: Create Xcode Project

Since we can't commit the Xcode project file directly, you'll need to create it:

1. Open Xcode
2. File → New → Project
3. Choose **macOS** → **App**
4. Fill in:
   - Product Name: `WriteBetter`
   - Team: Your team
   - Organization Identifier: `com.yourname` (or your preferred identifier)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Use Core Data"
   - Uncheck "Include Tests"
5. Save the project in the `WriteBetter` folder (the one containing all the .swift files)

## Step 3: Add Files to Xcode Project

Xcode should automatically detect all the `.swift` files. If not:

1. In the Project Navigator, right-click on the "WriteBetter" folder
2. Select "Add Files to WriteBetter..."
3. Select all the folders (Managers, Services, Views, Models, Utils)
4. Make sure "Copy items if needed" is **unchecked**
5. Make sure "Create groups" is selected
6. Click "Add"

## Step 4: Configure Project Settings

### Info.plist
1. Select the WriteBetter target
2. Go to "Info" tab
3. Click "Choose Info.plist File..."
4. Select `WriteBetter/Info.plist`

### Entitlements
1. Go to "Signing & Capabilities" tab
2. Under "App Sandbox", switch to the "WriteBetter.entitlements" file
3. Or manually add the entitlements file:
   - Click the "+" button under "Capability"
   - Add "App Sandbox" then disable it (set to NO)
   - Add "Hardened Runtime"

### Build Settings
1. Select the WriteBetter target
2. Go to "Build Settings"
3. Search for "Info.plist File"
4. Set it to: `WriteBetter/Info.plist`
5. Search for "Code Signing Entitlements"
6. Set it to: `WriteBetter/WriteBetter.entitlements`
7. Search for "macOS Deployment Target"
8. Set to: `12.0` or later

### Signing
1. Go to "Signing & Capabilities"
2. Select your development team
3. Xcode will automatically manage signing

## Step 5: Build and Run

1. Select "My Mac" as the build target
2. Press `Cmd+R` to build and run
3. The app will launch and request Accessibility permissions
4. Grant the permissions in System Preferences
5. The WriteBetter icon should appear in your menu bar

## Step 6: Test It Out

1. Open any text editor (Notes, TextEdit, etc.)
2. Type some text: "this is a test"
3. Select the text
4. Press `Cmd+Shift+Space`
5. The WriteBetter popup should appear with improved text!

## Troubleshooting

### Build Errors

**"No such module 'Carbon'"**
- Make sure your deployment target is macOS 12.0 or later

**"Cannot find type 'X' in scope"**
- Check that all files are added to the target
- Clean build folder: Product → Clean Build Folder
- Rebuild: `Cmd+B`

### Runtime Issues

**Hotkey doesn't work**
1. Open System Preferences
2. Go to Security & Privacy → Privacy
3. Select "Accessibility"
4. Make sure WriteBetter is checked
5. If not there, click "+", navigate to your build folder, and add WriteBetter.app
6. Restart the app

**"Invalid API Key" error**
1. Check your `.env` file has the correct key
2. Make sure there are no extra spaces or quotes
3. Verify the key is valid at console.anthropic.com

**Window doesn't appear**
- Make sure you selected text before pressing the hotkey
- Check Console.app for any error messages
- Try clicking in the text editor first, then selecting and triggering

## Development Tips

### Debugging
- Use `print()` statements to debug
- Check Console.app for app logs
- Use Xcode's debugger with breakpoints

### Hot Reload
- SwiftUI previews work for individual views
- For testing the full app, you'll need to rebuild

### Testing Different Scenarios
- Test with different text lengths
- Test in different apps (Safari, TextEdit, Xcode, etc.)
- Test with multi-line text
- Test the quick actions and custom prompts

## Next Steps

Once everything is working:
- Customize the quick actions to your preferences
- Adjust the prompt templates in `ImprovementRequest.swift`
- Experiment with different Claude models in `Constants.swift`
- Consider adding more AI providers (OpenAI, Gemini, etc.)

Enjoy using WriteBetter!
