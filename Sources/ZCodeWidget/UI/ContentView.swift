import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("ZCode Widget")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()

                // Minimize to menu bar
                Button(action: {
                    hideWidget()
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide to menu bar (Z icon)")

                // Close — hides window; reopen via Z menu bar icon or ⌘⇧Z
                Button(action: {
                    hideWidget()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide (reopen via Z menu bar icon or ⌘⇧Z)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            TabView(selection: $selectedTab) {
                TokensView()
                    .tabItem {
                        Label("Tokens", systemImage: "chart.bar.fill")
                    }
                    .tag(0)

                SkillsView()
                    .tabItem {
                        Label("Skills", systemImage: "wand.and.stars")
                    }
                    .tag(1)

                PluginsView()
                    .tabItem {
                        Label("Plugins", systemImage: "puzzlepiece.extension.fill")
                    }
                    .tag(2)

                ProvidersView()
                    .tabItem {
                        Label("Providers", systemImage: "server.rack")
                    }
                    .tag(3)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func hideWidget() {
        // Find the widget window specifically (it has a distinctive title)
        if let window = NSApp.windows.first(where: { $0.title == "ZCode Widget" }) {
            window.orderOut(nil)
        } else if let window = NSApp.keyWindow {
            window.orderOut(nil)
        } else {
            // Fallback: hide all windows
            for window in NSApp.windows where window.isVisible {
                window.orderOut(nil)
            }
        }
    }
}
