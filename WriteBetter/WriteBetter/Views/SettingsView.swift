import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = Constants.loadAPIKey() ?? ""
    @State private var showingAPIKeyInfo = false

    private var hasValidAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anthropic API Key")
                                .font(.headline)

                            SecureField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiKey) { newValue in
                                    Constants.saveAPIKey(newValue)
                                }

                            HStack(spacing: 4) {
                                Image(systemName: hasValidAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(hasValidAPIKey ? .green : .orange)
                                    .imageScale(.small)
                                Text(hasValidAPIKey ? "API key configured" : "API key required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Configuration")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("About WriteBetter")
                                .font(.headline)
                        }

                        Text("WriteBetter is a macOS utility that improves your text using AI.")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to use:")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Select any text in any app", systemImage: "1.circle.fill")
                                Label("Press Cmd+Shift+Space", systemImage: "2.circle.fill")
                                Label("Review and customize the improved text", systemImage: "3.circle.fill")
                                Label("Copy and paste", systemImage: "4.circle.fill")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requirements:")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Anthropic API key (get from console.anthropic.com)", systemImage: "key")
                                Label("Accessibility permissions (will be requested on first use)", systemImage: "checkmark.shield")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Link("Get API Key", destination: URL(string: "https://console.anthropic.com/")!)
                            Text("•")
                                .foregroundColor(.secondary)
                            Link("Documentation", destination: URL(string: "https://docs.anthropic.com/")!)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Information")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 550, height: 500)
    }
}

#Preview {
    SettingsView()
}
