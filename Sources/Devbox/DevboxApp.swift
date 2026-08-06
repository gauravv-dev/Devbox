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

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            DevTool.tools.first(where: { $0.id == selection })?.builder()
                .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
