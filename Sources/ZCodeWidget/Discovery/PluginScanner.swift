import Foundation

/// Scans ~/.zcode/cli/ for installed plugins using installed_plugins.json + config.json,
/// then reads plugin.json from each plugin's installPath for version/description.
final class PluginScanner {
    private let cliDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zcode/cli").path

    func scan() -> [PluginInfo] {
        var plugins: [PluginInfo] = []

        let installed = readInstalledPlugins()
        let enabled = readEnabledState()

        for installedPlugin in installed {
            let pluginId = installedPlugin["id"] as? String ?? ""
            let name = installedPlugin["name"] as? String ?? pluginId
            let version = installedPlugin["version"] as? String ?? "0.0.0"
            let installPath = installedPlugin["installPath"] as? String ?? ""

            // Skip if not installed or no install path
            guard !installPath.isEmpty, FileManager.default.fileExists(atPath: installPath) else {
                continue
            }

            let enabledState = enabled[pluginId] ?? enabled[name] ?? false

            // Read plugin.json for metadata. Try the install path root first,
            // then common sub-directories where plugin.json may live.
            var description = ""
            var resolvedVersion = version

            if let meta = readPluginJSON(at: installPath) {
                if let d = meta["description"] as? String, !d.isEmpty {
                    description = d
                }
                if let v = meta["version"] as? String, !v.isEmpty {
                    resolvedVersion = v
                }
            }

            plugins.append(PluginInfo(
                id: pluginId,
                name: name,
                version: resolvedVersion,
                description: description,
                path: installPath,
                skillNames: scanSkills(in: installPath),
                isEnabled: enabledState
            ))
        }

        return plugins.sorted { $0.name < $1.name }
    }

    // MARK: - File reading helpers

    /// Reads ~/.zcode/cli/plugins/installed_plugins.json → returns the `plugins` array.
    private func readInstalledPlugins() -> [[String: Any]] {
        let path = "\(cliDir)/plugins/installed_plugins.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["plugins"] as? [[String: Any]] else {
            return []
        }
        return list
    }

    /// Reads ~/.zcode/cli/config.json → returns the `plugins.enabledPlugins` map.
    private func readEnabledState() -> [String: Bool] {
        let path = "\(cliDir)/config.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any],
              let enabled = plugins["enabledPlugins"] as? [String: Bool] else {
            return [:]
        }
        return enabled
    }

    /// Reads the first plugin.json found at: installPath/plugin.json,
    /// installPath/.zcode-plugin/plugin.json, installPath/.claude-plugin/plugin.json,
    /// installPath/<version>/plugin.json, or installPath/<version>/<marketplace>/plugin.json
    private func readPluginJSON(at installPath: String) -> [String: Any]? {
        var candidates: [String] = [
            "plugin.json",
            ".zcode-plugin/plugin.json",
            ".claude-plugin/plugin.json",
            ".plugin/plugin.json"
        ]

        // Add any <version>/plugin.json candidates found in subdirectories
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: installPath) {
            for subdir in subdirs.filter({ !$0.hasPrefix(".") }) {
                candidates.append("\(subdir)/plugin.json")
                // Also check <version>/<marketplace>/...
                let subPath = "\(installPath)/\(subdir)"
                if let nested = try? FileManager.default.contentsOfDirectory(atPath: subPath) {
                    for n in nested where !n.hasPrefix(".") {
                        candidates.append("\(subdir)/\(n)/plugin.json")
                    }
                }
            }
        }

        for candidate in candidates {
            let fullPath = "\(installPath)/\(candidate)"
            guard let data = FileManager.default.contents(atPath: fullPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return json
        }
        return nil
    }

    /// Scans an install path for available skill names (directories containing SKILL.md).
    private func scanSkills(in installPath: String) -> [String] {
        var skillNames: [String] = []
        let skillsDir = URL(fileURLWithPath: installPath).appendingPathComponent("skills")

        // Also check <installPath>/<version>/skills
        if !FileManager.default.fileExists(atPath: skillsDir.path) {
            if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: installPath) {
                for subdir in subdirs.filter({ !$0.hasPrefix(".") }) {
                    let versionSkills = URL(fileURLWithPath: installPath)
                        .appendingPathComponent(subdir)
                        .appendingPathComponent("skills")
                    if FileManager.default.fileExists(atPath: versionSkills.path) {
                        if let names = collectSkillNames(from: versionSkills) {
                            skillNames.append(contentsOf: names)
                        }
                    }
                }
            }
        } else {
            skillNames = collectSkillNames(from: skillsDir) ?? []
        }

        return skillNames.sorted()
    }

    private func collectSkillNames(from dir: URL) -> [String]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let names: [String] = contents.compactMap { item in
            guard item.hasDirectoryPath,
                  FileManager.default.fileExists(atPath: item.appendingPathComponent("SKILL.md").path) else {
                return nil
            }
            return item.lastPathComponent
        }
        return names
    }
}
