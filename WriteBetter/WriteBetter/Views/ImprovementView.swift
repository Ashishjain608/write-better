import SwiftUI

struct ImprovementView: View {
    let originalText: String
    let onClose: () -> Void

    @State private var improvedText: String = ""
    @State private var customPrompt: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showCopied: Bool = false

    private var aiService: AIService {
        let apiKey = Constants.loadAPIKey() ?? ""
        return ClaudeService(apiKey: apiKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WriteBetter")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Original text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(originalText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                    }

                    // Improved text or loading state
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Improved")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Improving...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(32)
                        } else if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        } else if !improvedText.isEmpty {
                            Text(improvedText)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Quick actions
            VStack(spacing: 12) {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(QuickAction.allCases, id: \.self) { action in
                        Button(action: {
                            improveWithAction(action)
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: action.icon)
                                Text(action.rawValue)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                    }
                }

                // Custom prompt
                HStack(spacing: 8) {
                    TextField("Custom instruction...", text: $customPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            improveWithCustomPrompt()
                        }

                    Button(action: improveWithCustomPrompt) {
                        Image(systemName: "arrow.right.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(customPrompt.isEmpty || isLoading)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Actions
            HStack {
                if showCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied!")
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                Spacer()

                Button("Copy & Close") {
                    copyToClipboard()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(improvedText.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            improveWithDefaultPrompt()
        }
    }

    private func improveWithDefaultPrompt() {
        let request = ImprovementRequest(originalText: originalText, action: nil, customPrompt: nil)
        performImprovement(request)
    }

    private func improveWithAction(_ action: QuickAction) {
        let request = ImprovementRequest(originalText: originalText, action: action, customPrompt: nil)
        performImprovement(request)
    }

    private func improveWithCustomPrompt() {
        guard !customPrompt.isEmpty else { return }
        let request = ImprovementRequest(originalText: originalText, action: nil, customPrompt: customPrompt)
        performImprovement(request)
        customPrompt = ""
    }

    private func performImprovement(_ request: ImprovementRequest) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await aiService.improveText(request: request)
                await MainActor.run {
                    improvedText = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(improvedText, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview {
    ImprovementView(
        originalText: "this is a test text that needs improvement",
        onClose: {}
    )
}
