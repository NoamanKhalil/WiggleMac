import Foundation

struct OllamaModel: Identifiable, Hashable, Sendable {
    let name: String
    let size: Int64
    let capabilities: [String]

    var id: String { name }
    var supportsVision: Bool { capabilities.contains("vision") }
}

/// Small models that run well on a Mac, offered in the download list.
struct CatalogModel: Identifiable, Sendable {
    let name: String
    let title: String
    let summary: String
    let sizeMB: Int
    let vision: Bool

    var id: String { name }

    static let all: [CatalogModel] = [
        CatalogModel(name: "qwen2.5:0.5b", title: "Qwen 2.5 0.5B", summary: "Tiny and very fast. Good for quick questions.", sizeMB: 398, vision: false),
        CatalogModel(name: "qwen3:0.6b", title: "Qwen 3 0.6B", summary: "Newest tiny Qwen, with reasoning.", sizeMB: 523, vision: false),
        CatalogModel(name: "gemma3:1b", title: "Gemma 3 1B", summary: "Google's small model. Clear, well-written answers.", sizeMB: 815, vision: false),
        CatalogModel(name: "deepseek-r1:1.5b", title: "DeepSeek R1 1.5B", summary: "Thinks step by step before answering.", sizeMB: 1117, vision: false),
        CatalogModel(name: "llama3.2:1b", title: "Llama 3.2 1B", summary: "Meta's small general-purpose model.", sizeMB: 1321, vision: false),
        CatalogModel(name: "qwen3:1.7b", title: "Qwen 3 1.7B", summary: "Noticeably smarter, still quick.", sizeMB: 1359, vision: false),
        CatalogModel(name: "moondream", title: "Moondream 2", summary: "Tiny vision model. Describes what's on screen.", sizeMB: 1738, vision: true),
        CatalogModel(name: "qwen3-vl:2b", title: "Qwen 3 VL 2B", summary: "Small vision model. Reads screenshots well.", sizeMB: 1890, vision: true),
        CatalogModel(name: "llama3.2:3b", title: "Llama 3.2 3B", summary: "Stronger general model for longer answers.", sizeMB: 2019, vision: false),
        CatalogModel(name: "qwen3:4b", title: "Qwen 3 4B", summary: "Best quality text model in this list.", sizeMB: 2497, vision: false),
        CatalogModel(name: "phi4-mini", title: "Phi-4 Mini", summary: "Microsoft's compact model. Strong at math and code.", sizeMB: 2492, vision: false),
        CatalogModel(name: "qwen2.5vl:3b", title: "Qwen 2.5 VL 3B", summary: "Vision model for documents, charts and UI.", sizeMB: 3201, vision: true),
        CatalogModel(name: "qwen3-vl:4b", title: "Qwen 3 VL 4B", summary: "Best screenshot understanding in this list.", sizeMB: 3296, vision: true),
        CatalogModel(name: "gemma3:4b", title: "Gemma 3 4B", summary: "Google's vision model. Good all-rounder.", sizeMB: 3339, vision: true),
    ]
}

/// Talks to a local Ollama server.
struct OllamaClient: Sendable {
    let host: URL

    func isRunning() async -> Bool {
        var request = URLRequest(url: host.appending(path: "api/version"))
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    func installedModels() async throws -> [OllamaModel] {
        let (data, _) = try await URLSession.shared.data(from: host.appending(path: "api/tags"))
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.models.map {
            OllamaModel(name: $0.name, size: $0.size, capabilities: $0.capabilities ?? [])
        }
    }

    /// Downloads a model, reporting progress (0...1, when known) and Ollama's status text.
    func pull(_ name: String, progress: @MainActor (Double?, String) -> Void) async throws {
        let request = try HTTP.jsonRequest(host.appending(path: "api/pull"), body: ["model": name, "stream": true])
        for try await line in try await HTTP.lines(for: request) {
            try Task.checkCancellation()
            let update = try JSONDecoder().decode(PullUpdate.self, from: Data(line.utf8))
            if let error = update.error {
                throw LLMError.server(error)
            }
            var fraction: Double?
            if let total = update.total, total > 0 {
                fraction = Double(update.completed ?? 0) / Double(total)
            }
            await progress(fraction, update.status ?? "")
        }
    }

    func delete(_ name: String) async throws {
        let request = try HTTP.jsonRequest(host.appending(path: "api/delete"), method: "DELETE", body: ["model": name])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw LLMError.server(HTTP.errorMessage(from: data) ?? "Couldn't delete \(name).")
        }
    }
}

private struct TagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let size: Int64
        let capabilities: [String]?
    }
    let models: [Model]
}

private struct PullUpdate: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
    let error: String?
}
