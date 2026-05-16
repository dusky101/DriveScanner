import Foundation

/// Builds a single self-contained HTML file with nested `<details>` trees.
public enum HTMLReportBuilder: Sendable {
    public static func buildHTML(
        title: String,
        tree: TreeWalkResult,
        generatedAt: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("<!DOCTYPE html>")
        lines.append("<html lang=\"en\">")
        lines.append("<head>")
        lines.append("<meta charset=\"utf-8\"/>")
        lines.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>")
        lines.append("<title>\(escape(title))</title>")
        lines.append(
            """
            <style>
              body { font-family: -apple-system, system-ui, sans-serif; margin: 1.25rem; line-height: 1.35; }
              h1 { font-size: 1.25rem; }
              .meta { color: #555; font-size: 0.9rem; margin-bottom: 1rem; }
              details { margin-left: 0.75rem; border-left: 1px solid #ddd; padding-left: 0.5rem; }
              summary { cursor: pointer; font-weight: 500; }
              .file { margin-left: 0.75rem; color: #333; }
              .warn { color: #a60; font-weight: 600; }
            </style>
            """
        )
        lines.append("</head>")
        lines.append("<body>")
        lines.append("<h1>\(escape(title))</h1>")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let truncatedSuffix =
            tree.truncated ? " <span class=\"warn\">(truncated)</span>" : ""
        let generatedEscaped = escape(formatter.string(from: generatedAt))
        lines.append(
            "<p class=\"meta\">Generated: \(generatedEscaped) · Entries visited: \(tree.entriesVisited)\(truncatedSuffix)</p>"
        )

        if tree.truncated {
            lines.append(
                "<p class=\"warn\">Listing was truncated by max depth or max entries. Re-scan with fewer selections or adjust limits in the app.</p>"
            )
        }

        lines.append("<div class=\"tree\">")
        for node in tree.rootNodes {
            appendNode(node, to: &lines, depth: 0)
        }
        lines.append("</div>")
        lines.append("</body>")
        lines.append("</html>")
        return lines.joined(separator: "\n")
    }

    private static func appendNode(_ node: FileTreeNode, to lines: inout [String], depth: Int) {
        if node.isDirectory {
            lines.append("<details open>")
            let summary = escape(node.name) + (node.url.isFileURL ? " <span style=\"color:#888;font-weight:400;\">\(escape(node.url.path))</span>" : "")
            lines.append("<summary>\(summary)</summary>")
            for child in node.children {
                appendNode(child, to: &lines, depth: depth + 1)
            }
            lines.append("</details>")
        } else {
            lines.append("<div class=\"file\">\(escape(node.name)) — <code>\(escape(node.url.path))</code></div>")
        }
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&#39;")
            default:
                if ch.value < 32 || ch.value == 0x7F {
                    out.append("&#\(ch.value);")
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }
}
