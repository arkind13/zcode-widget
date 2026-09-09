import Foundation

/// Scans ~/.zcode/skills/ for available skills
final class SkillScanner {
    func scan() -> [SkillInfo] {
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zcode/skills")
        var skills: [SkillInfo] = []
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil)
            
            for item in contents {
                let skillName = item.lastPathComponent
                let skillYML = item.appendingPathComponent("SKILL.md")
                
                var description = ""
                var source = "local"
                
                if FileManager.default.fileExists(atPath: skillYML.path) {
                    do {
                        let content = try String(contentsOf: skillYML, encoding: .utf8)
                        description = Self.parseDescription(from: content)
                    } catch {
                        description = "Error reading skill description"
                    }
                }
                
                // Check if it's a plugin skill
                if skillName.contains("plugin") || skillsDir.path.contains("plugin") {
                    source = "plugin"
                }
                
                skills.append(SkillInfo(
                    id: skillName,
                    name: skillName,
                    description: description,
                    path: item.path,
                    source: source
                ))
            }
        } catch {
            print("SkillScanner.scan error: \(error)")
        }
        
        return skills.sorted { $0.name < $1.name }
    }

    // MARK: - YAML frontmatter parsing

    /// Parses `name:` and `description:` out of a SKILL.md's YAML frontmatter.
    /// Falls back to legacy Chinese (`文档介绍：`) / English (`Description:`) inline patterns.
    static func parseDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)

        // Try YAML frontmatter first (block delimited by `---` at the top of the file)
        if let fm = parseYAMLFrontmatter(lines) {
            if !fm.description.isEmpty { return fm.description }
            if !fm.name.isEmpty { return fm.name }
        }

        // Fallback: legacy inline patterns
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("文档介绍：") {
                return String(trimmed.dropFirst("文档介绍：".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Description:") {
                return String(trimmed.dropFirst("Description:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private struct Frontmatter {
        let name: String
        let description: String
    }

    private static func parseYAMLFrontmatter(_ lines: [String]) -> Frontmatter? {
        // A frontmatter block must start with `---`
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var name = ""
        var description = ""
        var inBlock = false
        for line in lines[...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inBlock { break }          // closing fence
                inBlock = true
                continue
            }
            guard inBlock else { continue }
            // Stop at the first non-empty, non-comment line that isn't a key:value
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { break }

            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[colon...].dropFirst()).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if value.count >= 2,
               (value.first == "\"" && value.last == "\"") ||
               (value.first == "'" && value.last == "'") {
                value = String(value.dropFirst().dropLast())
            }

            switch key {
            case "name": name = value
            case "description": description = value
            default: break
            }
        }
        return Frontmatter(name: name, description: description)
    }
}