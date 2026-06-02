import Foundation

enum PromptRewriteService {
    static func rewrite(
        originalPrompt: String,
        projectContext: ProjectContext,
        targetKind: TargetAppKind,
        targetAppName: String,
        captureSource: String,
        settings: RewriteSettings
    ) async throws -> String {
        let rewritten = try await requestRewrite(
            originalPrompt: originalPrompt,
            projectContext: projectContext,
            targetKind: targetKind,
            targetAppName: targetAppName,
            captureSource: captureSource,
            settings: settings,
            mode: .standard
        )

        if introducesUnexpectedSpecifics(
            originalPrompt: originalPrompt,
            rewrittenPrompt: rewritten,
            targetKind: targetKind
        ) {
            return try await requestRewrite(
                originalPrompt: originalPrompt,
                projectContext: projectContext,
                targetKind: targetKind,
                targetAppName: targetAppName,
                captureSource: captureSource,
                settings: settings,
                mode: .intentCorrection
            )
        }

        if needsSubstantiveRetry(
            originalPrompt: originalPrompt,
            rewrittenPrompt: rewritten,
            targetKind: targetKind
        ) {
            return try await requestRewrite(
                originalPrompt: originalPrompt,
                projectContext: projectContext,
                targetKind: targetKind,
                targetAppName: targetAppName,
                captureSource: captureSource,
                settings: settings,
                mode: .substantiveRetry
            )
        }

        return rewritten
    }

    private static func requestRewrite(
        originalPrompt: String,
        projectContext: ProjectContext,
        targetKind: TargetAppKind,
        targetAppName: String,
        captureSource: String,
        settings: RewriteSettings,
        mode: RewriteMode
    ) async throws -> String {
        guard let url = endpointURL(from: settings.baseURL) else {
            throw RewriteServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: settings.model.isEmpty ? "deepseek-v4-flash" : settings.model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt(targetKind: targetKind, mode: mode)),
                ChatMessage(
                    role: "user",
                    content: userPrompt(
                        originalPrompt: originalPrompt,
                        projectContext: projectContext,
                        targetKind: targetKind,
                        targetAppName: targetAppName,
                        captureSource: captureSource,
                        mode: mode
                    )
                )
            ],
            thinking: ThinkingSetting(type: "disabled"),
            temperature: mode.temperature(for: targetKind),
            maxTokens: 1_400,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if !(200..<300).contains(statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw RewriteServiceError.apiError(errorResponse.error.message)
            }
            let text = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw RewriteServiceError.apiError(text)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw RewriteServiceError.emptyResponse
        }

        return stripCodeFence(from: content)
    }

    private static func systemPrompt(targetKind: TargetAppKind, mode: RewriteMode) -> String {
        """
        You rewrite the user's rough text so it is ready to paste back into the currently focused app.
        Output ONLY the replacement text. Do not answer it, do not explain, and do not wrap it in a code fence.

        Hard rules — never break these:
        - Preserve the user's intent and the EXACT action they ask for. Keep the imperative verb's meaning.
          If the user says to do / implement / build / fix something, the rewrite must still tell the
          assistant to DO / implement / build / fix it — never downgrade it to "describe", "summarize",
          "explain", or "write about" it.
        - Keep the same language as the user for normal text. For terminal commands, keep valid shell syntax.
        - Treat references to files, plans, or docs (e.g. "the implementation plan") as things to OPEN and
          ACT ON, not as topics to write about.
        - Choose the length by usefulness, not by the original size. Short terminal commands and normal
          human messages can stay short. Rough AI-assistant prompts should become specific enough for an
          assistant to act on without guessing.
        - Do not invent unrelated scope, fake facts, credentials, file names, dates, or business claims.
          You may make practical details explicit when they are clearly implied by the user's request.
        - Do not reuse named tools, apps, platforms, channels, products, or CTA words from old requests.
          Every rewrite must be based only on the current "Original rough text" and the provided local context.
        - Keep the user's tone and any concrete constraints they gave.
        - Use the project context only to resolve what the user refers to, never to add new scope.
        - Never treat an internal plugin/cache/path shown by the UI as the user's request unless the user clearly typed that path as part of the request.
        \(mode.extraSystemRule)

        Target-specific rules:
        \(targetRules(for: targetKind))
        """
    }

    private static func targetRules(for targetKind: TargetAppKind) -> String {
        switch targetKind {
        case .codingAssistant:
            """
            - Rewrite as a clear instruction for an AI coding assistant.
            - Turn vague wishes into an actionable task: goal, expected result, important constraints,
              quality bar, and checks or acceptance criteria when useful.
            - For creative, video, design, plugin, or tool requests, preserve the selected tool/plugin name
              and include practical production details implied by the request: format, audience, content
              beats, visual style, final CTA/sales close, and deliverable.
            - For Instagram/Reels video requests with a sales ending or CTA, the final CTA must ask viewers
              to comment a short keyword under the post or Reel so the creator can follow up with an offer.
              Do not send viewers to Telegram, WhatsApp, a bot, or DMs unless the user explicitly asked for
              that channel.
            - Preserve selected tools, plugins, app names, and constraints exactly as the user intended.
            - If a plugin/tool is selected in the UI, do not replace the user's request with that plugin's local filesystem path.
            - Do not stop at punctuation-only cleanup unless the original is already a detailed, ready-to-run prompt.
            """
        case .terminal:
            """
            - The text is a shell command or a rough request for a shell command.
            - Return only the corrected command line. Do not add explanations, comments, prompts, or a trailing newline.
            - Do not add sudo or destructive flags unless the user clearly requested them.
            - Prefer a safe command that the user can inspect before running.
            """
        case .codeEditor:
            """
            - Rewrite as a concise editing or coding instruction for the current project/editor.
            - Keep file names, symbols, and concrete actions intact.
            """
        case .messaging:
            """
            - Rewrite as a human message for the chat or mail app.
            - Do not turn it into an AI prompt, task plan, ticket, or coding instruction.
            - Keep the tone natural and preserve names, dates, numbers, and intent.
            """
        case .browser, .general:
            """
            - Rewrite as polished text for the active app.
            - Do not assume the user is asking a coding assistant.
            - Do not add project details unless they are already in the original text.
            """
        }
    }

    private static func userPrompt(
        originalPrompt: String,
        projectContext: ProjectContext,
        targetKind: TargetAppKind,
        targetAppName: String,
        captureSource: String,
        mode: RewriteMode
    ) -> String {
        """
        Target app: \(targetAppName)
        Target type: \(targetKind.rawValue)
        Capture source: \(captureSource)

        Original rough text:
        \(originalPrompt)

        Local project context:
        \(projectContext.summary)

        \(mode.extraUserInstruction)

        Rewrite ONLY the current rough text above so it is ready to paste back into \(targetAppName).
        """
    }

    private static func needsSubstantiveRetry(
        originalPrompt: String,
        rewrittenPrompt: String,
        targetKind: TargetAppKind
    ) -> Bool {
        guard targetKind == .codingAssistant else { return false }

        let originalSignature = semanticSignature(from: originalPrompt)
        let rewrittenSignature = semanticSignature(from: rewrittenPrompt)

        guard originalSignature.count >= 20 else { return false }
        return originalSignature == rewrittenSignature
    }

    private static func introducesUnexpectedSpecifics(
        originalPrompt: String,
        rewrittenPrompt: String,
        targetKind: TargetAppKind
    ) -> Bool {
        guard targetKind == .codingAssistant else { return false }

        let original = originalPrompt.lowercased()
        let rewritten = rewrittenPrompt.lowercased()

        return watchedSpecificTerms.contains { term in
            rewritten.contains(term) && !original.contains(term)
        }
    }

    private static let watchedSpecificTerms = [
        "remotion",
        "re motion",
        "instagram",
        "инстаграм",
        "reels",
        "рилс",
        "telegram",
        "телеграм"
    ]

    private static func semanticSignature(from text: String) -> String {
        var result = ""

        for scalar in text.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }

        return result
    }

    private static func endpointURL(from baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return URL(string: "\(trimmed)/chat/completions")
    }

    private static func stripCodeFence(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 3 {
                trimmed = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }

        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RewriteMode {
    case standard
    case substantiveRetry
    case intentCorrection

    var extraSystemRule: String {
        switch self {
        case .standard:
            ""
        case .substantiveRetry:
            "- The previous rewrite was too close to the original. Make the rewrite meaningfully stronger while preserving the user's intent."
        case .intentCorrection:
            "- The previous rewrite introduced a tool, platform, channel, or app that was not in the current user text. Remove that invented detail and rewrite again from the current text only."
        }
    }

    var extraUserInstruction: String {
        switch self {
        case .standard:
            ""
        case .substantiveRetry:
            """
            The first rewrite looked like punctuation-only cleanup. Rewrite again and make it substantively better:
            clarify the task, add implied practical details, and make the final instruction ready for an AI assistant to execute.
            """
        case .intentCorrection:
            """
            The first rewrite introduced a named tool, platform, app, or channel that was not in the current rough text.
            Rewrite again without importing details from earlier prompts or examples.
            """
        }
    }

    func temperature(for targetKind: TargetAppKind) -> Double {
        switch self {
        case .substantiveRetry:
            return 0.45
        case .intentCorrection:
            return 0.15
        case .standard:
            switch targetKind {
            case .codingAssistant:
                return 0.35
            case .codeEditor:
                return 0.25
            case .messaging, .browser, .general:
                return 0.2
            case .terminal:
                return 0.0
            }
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let thinking: ThinkingSetting
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ThinkingSetting: Encodable {
    let type: String
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatMessage
    }

    let choices: [Choice]
}

private struct APIErrorResponse: Decodable {
    let error: APIError
}

private struct APIError: Decodable {
    let message: String
}

enum RewriteServiceError: LocalizedError {
    case invalidBaseURL
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "API base URL is invalid"
        case .apiError(let message):
            "API error: \(message)"
        case .emptyResponse:
            "API returned an empty rewrite"
        }
    }
}
