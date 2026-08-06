import SwiftUI

struct Sidebar: View {
    @Binding var selection: ToolKind
    @State private var query = ""

    private var filtered: [DevTool] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return DevTool.tools }
        return DevTool.tools.filter {
            $0.name.lowercased().contains(q) || $0.keywords.contains { $0.contains(q) }
        }
    }

    var body: some View {
        List(selection: Binding<ToolKind?>(
            get: { selection },
            set: { if let v = $0 { selection = v } }
        )) {
            ForEach(ToolCategory.allCases) { category in
                let tools = filtered.filter { $0.category == category }
                if !tools.isEmpty {
                    Section(category.rawValue) {
                        ForEach(tools) { tool in
                            Label(tool.name, systemImage: tool.icon)
                                .tag(tool.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .automatic, prompt: "Search tools")
        .navigationTitle("Devbox")
    }
}
