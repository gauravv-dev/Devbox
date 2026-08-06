import Foundation

/// LCS-based line diff engine.
enum DiffEngine {
    enum ChangeKind { case same, added, removed }
    struct Change {
        let kind: ChangeKind
        let text: String
    }

    /// Diffs two documents line-by-line. Returns nil when inputs are too large
    /// for the O(N*M) table (keeps memory bounded).
    static func diff(a: [String], b: [String]) -> [Change]? {
        let n = a.count, m = b.count
        if n == 0 && m == 0 { return [] }
        guard (n + 1) * (m + 1) <= 8_000_000 else { return nil }

        let width = m + 1
        var dp = [Int32](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            let rowBase = i * width
            for j in stride(from: m - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    dp[rowBase + j] = dp[rowBase + width + j + 1] + 1
                } else {
                    let down = dp[rowBase + width + j]
                    let right = dp[rowBase + j + 1]
                    dp[rowBase + j] = down >= right ? down : right
                }
            }
        }

        var out: [Change] = []
        out.reserveCapacity(n + m)
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                out.append(Change(kind: .same, text: a[i])); i += 1; j += 1
            } else if dp[(i + 1) * width + j] >= dp[i * width + j + 1] {
                out.append(Change(kind: .removed, text: a[i])); i += 1
            } else {
                out.append(Change(kind: .added, text: b[j])); j += 1
            }
        }
        while i < n { out.append(Change(kind: .removed, text: a[i])); i += 1 }
        while j < m { out.append(Change(kind: .added, text: b[j])); j += 1 }
        return out
    }

    static func splitLines(_ s: String) -> [String] {
        s.isEmpty ? [] : s.components(separatedBy: "\n")
    }
}
