import SwiftUI

struct PluginsView: View {
    @State private var plugins: [PluginInfo] = []
    @State private var searchText = ""
    @State private var toastMessage: String?

    private let scanner = PluginScanner()

    var filtered: [PluginInfo] {
        if searchText.isEmpty { return plugins }
        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { plugin in
                        PluginRow(plugin: plugin) {
                            let cmd = "/\(plugin.name)"
                            copyToClipboard(cmd, label: plugin.name)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            plugins = scanner.scan()
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
    }

    private func copyToClipboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastMessage = "Copied \(text)"
    }
}

// MARK: - PluginRow

struct PluginRow: View {
    let plugin: PluginInfo
    let onCopy: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(plugin.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("v\(plugin.version)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(plugin.description.isEmpty ? "\(plugin.skillNames.count) skill(s)" : plugin.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy /\(plugin.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onTapGesture { onCopy() }
    }
}
