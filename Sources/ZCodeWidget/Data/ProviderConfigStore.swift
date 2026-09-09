import Foundation
import AppKit

// MARK: - Typed views over the raw provider registry
//
// The store loads ~/.zcode/v2/config.json with JSONSerialization into
// [String: Any] so every field the widget does not understand (zcode
// metadata, systemDisabledReason, …) survives a round-trip untouched.
// These structs are typed read/edit models over that raw tree; saving
// writes only the keys the widget manages back into the raw dicts.

struct ProviderModelConfig: Identifiable, Equatable {
    var id: String                 // registry key == model id sent to the gateway
    var name: String               // optional display name; empty = omit key
    var reasoningEnabled: Bool
    var hasReasoning: Bool         // whether the model config carries a reasoning block
    var reasoningVariants: [String]
    var defaultVariant: String
    var contextLimit: Int
    var outputLimit: Int           // 0 = omit "output" key
    var inputModalities: [String]
    var outputModalities: [String]
}

struct ProviderConfig: Identifiable, Equatable {
    var id: String                 // registry key ("builtin:…" or UUID)
    var name: String
    var kind: String               // "anthropic" | "openai-compatible"
    var baseURL: String
    var apiKey: String
    var apiKeyRequired: Bool
    var enabled: Bool
    var headers: [HeaderPair]      // custom outbound headers
    var models: [ProviderModelConfig]
    var systemDisabledReason: String?

    var isBuiltin: Bool { id.hasPrefix("builtin:") }

    struct HeaderPair: Identifiable, Equatable {
        var id = UUID()
        var key: String
        var value: String
    }
}

// MARK: - Store

final class ProviderConfigStore: ObservableObject {
    @Published var providers: [ProviderConfig] = []
    @Published var loadError: String?

    /// Default: the live ZCode IDE provider registry. Overridable for tests.
    static var configPath = NSHomeDirectory() + "/.zcode/v2/config.json"
    private var root: [String: Any] = [:]

    var configURL: URL { URL(fileURLWithPath: Self.configPath) }

    // MARK: Load

    func load() {
        loadError = nil
        do {
            guard FileManager.default.fileExists(atPath: Self.configPath) else {
                loadError = "Config not found at ~/.zcode/v2/config.json"
                providers = []
                return
            }
            let data = try Data(contentsOf: configURL)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else {
                loadError = "Config root is not a JSON object"
                return
            }
            root = dict
            providers = Self.parseProviders(from: dict)
        } catch {
            loadError = "Failed to read config: \(error.localizedDescription)"
        }
    }

    private static func parseProviders(from root: [String: Any]) -> [ProviderConfig] {
        let registry = root["provider"] as? [String: Any] ?? [:]
        return registry
            .compactMap { (id, raw) -> ProviderConfig? in
                guard let dict = raw as? [String: Any] else { return nil }
                return parseProvider(id: id, dict)
            }
            .sorted { a, b in
                if a.isBuiltin != b.isBuiltin { return !a.isBuiltin }   // custom providers first
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private static func parseProvider(id: String, _ dict: [String: Any]) -> ProviderConfig {
        let options = dict["options"] as? [String: Any] ?? [:]
        let headersRaw = (dict["headers"] as? [String: Any])
            ?? (options["headers"] as? [String: Any]) ?? [:]
        let models = (dict["models"] as? [String: Any] ?? [:])
            .compactMap { (modelId, raw) -> ProviderModelConfig? in
                guard let m = raw as? [String: Any] else { return nil }
                return parseModel(id: modelId, m)
            }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }

        return ProviderConfig(
            id: id,
            name: dict["name"] as? String ?? id,
            kind: dict["kind"] as? String ?? "anthropic",
            baseURL: options["baseURL"] as? String ?? "",
            apiKey: options["apiKey"] as? String ?? "",
            apiKeyRequired: options["apiKeyRequired"] as? Bool ?? false,
            enabled: dict["enabled"] as? Bool ?? true,
            headers: headersRaw
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { ProviderConfig.HeaderPair(key: $0.key, value: $0.value as? String ?? "") },
            models: models,
            systemDisabledReason: dict["systemDisabledReason"] as? String
        )
    }

    private static func parseModel(id: String, _ m: [String: Any]) -> ProviderModelConfig {
        let reasoning = m["reasoning"] as? [String: Any]
        let limit = m["limit"] as? [String: Any] ?? [:]
        let modalities = m["modalities"] as? [String: Any] ?? [:]
        return ProviderModelConfig(
            id: id,
            name: m["name"] as? String ?? "",
            reasoningEnabled: reasoning?["enabled"] as? Bool ?? false,
            hasReasoning: reasoning != nil,
            reasoningVariants: reasoning?["variants"] as? [String] ?? [],
            defaultVariant: reasoning?["defaultVariant"] as? String ?? "",
            contextLimit: limit["context"] as? Int ?? 0,
            outputLimit: limit["output"] as? Int ?? 0,
            inputModalities: modalities["input"] as? [String] ?? [],
            outputModalities: modalities["output"] as? [String] ?? []
        )
    }

    // MARK: Save

    /// Writes the edited provider back into the raw tree (preserving all
    /// unknown keys), creates a timestamped backup, then replaces the file
    /// atomically. Throws on any I/O or serialization failure.
    func save(_ provider: ProviderConfig, isNew: Bool) throws {
        if root.isEmpty { load() }

        // Casts of bridged NSDictionaries copy on mutation (Swift CoW), and every
        // mutated dict is reassigned up the chain, so unknown keys survive intact.
        var registry = root["provider"] as? [String: Any] ?? [:]
        if isNew {
            // New provider skeleton — mirrors what the ZCode settings UI creates
            registry[provider.id] = [
                "name": provider.name,
                "kind": provider.kind,
                "source": "custom"
            ] as [String: Any]
        }
        guard var provDict = registry[provider.id] as? [String: Any] else {
            throw ProviderStoreError.providerNotFound(provider.id)
        }

        // -- provider-level keys the widget manages
        provDict["name"] = provider.name
        provDict["kind"] = provider.kind
        if !provider.enabled {
            provDict["enabled"] = false
        } else if provDict["enabled"] as? Bool == false {
            provDict["enabled"] = true
        }

        // -- options block (surgical: keep unknown option keys)
        var options = (provDict["options"] as? [String: Any]) ?? [:]
        options["apiKey"] = provider.apiKey
        options["baseURL"] = provider.baseURL
        options["apiKeyRequired"] = provider.apiKeyRequired

        // -- headers: write both places ZCode reads (provider-level + options)
        let headersDict = Dictionary(
            provider.headers.filter { !$0.key.isEmpty && !$0.value.isEmpty }
                .map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        if headersDict.isEmpty {
            provDict.removeValue(forKey: "headers")
            options.removeValue(forKey: "headers")
        } else {
            provDict["headers"] = headersDict
            options["headers"] = headersDict
        }
        provDict["options"] = options

        // -- models (surgical per model: preserve zcode metadata etc.)
        var models = (provDict["models"] as? [String: Any]) ?? [:]
        var seen = Set<String>()
        for model in provider.models {
            seen.insert(model.id)
            var m = (models[model.id] as? [String: Any]) ?? [:]
            if model.name.isEmpty {
                m.removeValue(forKey: "name")
            } else {
                m["name"] = model.name
            }
            if model.hasReasoning || model.reasoningEnabled {
                m["reasoning"] = [
                    "enabled": model.reasoningEnabled,
                    "variants": model.reasoningVariants,
                    "defaultVariant": model.defaultVariant
                ] as [String: Any]
            } else if m["reasoning"] != nil {
                m.removeValue(forKey: "reasoning")
            }
            var limit = (m["limit"] as? [String: Any]) ?? [:]
            limit["context"] = model.contextLimit
            if model.outputLimit > 0 {
                limit["output"] = model.outputLimit
            } else {
                limit.removeValue(forKey: "output")
            }
            m["limit"] = limit
            m["modalities"] = [
                "input": model.inputModalities,
                "output": model.outputModalities
            ] as [String: Any]
            models[model.id] = m
        }
        // models removed in the editor — drop their keys
        for key in models.keys where !seen.contains(key) {
            models.removeValue(forKey: key)
        }
        provDict["models"] = models

        registry[provider.id] = provDict
        root["provider"] = registry

        try persist()
        providers = Self.parseProviders(from: root)
    }

    func deleteProvider(id: String) throws {
        if root.isEmpty { load() }
        guard var registry = root["provider"] as? [String: Any] else { return }
        guard registry[id] != nil else { return }
        registry.removeValue(forKey: id)
        root["provider"] = registry
        try persist()
        providers = Self.parseProviders(from: root)
    }

    // MARK: Persistence helpers

    private func persist() throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try Self.backup(fileURL: configURL)
        let tmp = configURL.appendingPathExtension("tmp-widget")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: configURL.path) {
            _ = try FileManager.default.replaceItemAt(configURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: configURL)
        }
    }

    /// Copies the config to config.json.bak-widget-<timestamp>, keeping the newest 10.
    static func backup(fileURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let stamp = DateFormatter(format: "yyyyMMdd-HHmmss").string(from: Date())
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("config.json.bak-widget-\(stamp)")
        try? fm.removeItem(at: backupURL)
        try fm.copyItem(at: fileURL, to: backupURL)

        // prune old backups beyond 10
        let dir = fileURL.deletingLastPathComponent().path
        let backups = (try? fm.contentsOfDirectory(atPath: dir))?
            .filter { $0.hasPrefix("config.json.bak-widget-") }
            .sorted() ?? []
        if backups.count > 10 {
            for name in backups.prefix(backups.count - 10) {
                try? fm.removeItem(atPath: dir + "/" + name)
            }
        }
    }

    // MARK: Environment checks

    static func isZCodeRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "dev.zcode.app").contains { !$0.isTerminated }
    }

    // MARK: Factory

    static func newProviderTemplate() -> ProviderConfig {
        ProviderConfig(
            id: UUID().uuidString.lowercased(),
            name: "",
            kind: "anthropic",
            baseURL: "",
            apiKey: "",
            apiKeyRequired: true,
            enabled: true,
            headers: [],
            models: [],
            systemDisabledReason: nil
        )
    }

    static func newModelTemplate(id: String = "") -> ProviderModelConfig {
        ProviderModelConfig(
            id: id,
            name: "",
            reasoningEnabled: true,
            hasReasoning: true,
            reasoningVariants: ["low", "high", "max"],
            defaultVariant: "max",
            contextLimit: 1_000_000,
            outputLimit: 128_000,
            inputModalities: ["text"],
            outputModalities: ["text"]
        )
    }
}

enum ProviderStoreError: LocalizedError {
    case providerNotFound(String)

    var errorDescription: String? {
        switch self {
        case .providerNotFound(let id):
            return "Provider \(id) disappeared from config.json — reload and try again."
        }
    }
}

private extension DateFormatter {
    convenience init(format: String) {
        self.init()
        self.dateFormat = format
    }
}
