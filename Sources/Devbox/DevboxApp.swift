import SwiftUI

@main
struct DevboxApp: App {
    @AppStorage("selectedTool") private var selectedToolRaw: String = ToolKind.json.rawValue

    var body: some Scene {
        WindowGroup("Devbox") {
            ContentView(selection: Binding(
                get: { ToolKind(rawValue: selectedToolRaw) ?? .json },
                set: { selectedToolRaw = $0.rawValue }
            ))
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 640)
    }
}

struct ContentView: View {
    @Binding var selection: ToolKind
    @AppStorage("devbox.launchInProgress") private var launchInProgress = false
    @State private var recovered = false

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            DevTool.tools.first(where: { $0.id == selection })?.builder()
                .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .top) {
            if recovered { RecoveryBanner(onDismiss: { recovered = false }) }
        }
        .onAppear(perform: runLaunchGuard)
    }

    /// Crash-loop guard: if the previous launch left its "in progress" sentinel set,
    /// it crashed before reaching a stable state — fall back to a safe tool instead of
    /// restoring the one that crashed.
    private func runLaunchGuard() {
        if launchInProgress {
            selection = .json
            recovered = true
        }
        launchInProgress = true
        UserDefaults.standard.synchronize()
        // Window has built and the first render survived → clear the sentinel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            launchInProgress = false
            UserDefaults.standard.synchronize()
        }
    }
}

private struct RecoveryBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lifepreserver")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Restored to a safe screen").font(.callout.weight(.semibold))
                Text("Devbox crashed while loading the last tool. Pick another tool from the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss", action: onDismiss).controlSize(.small)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
