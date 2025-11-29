import Foundation

class ClaudeService: AIService {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func improveText(request: ImprovementRequest) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let url = URL(string: Constants.anthropicAPIURL)!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = request.buildPrompt()

        let body: [String: Any] = [
            "model": Constants.defaultModel,
            "max_tokens": Constants.maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorDict["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw AIServiceError.apiError(message)
                }
                throw AIServiceError.apiError("Status code: \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw AIServiceError.invalidResponse
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
}
