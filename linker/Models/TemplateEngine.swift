import Foundation

struct TemplateEntry: Identifiable {
    let id: String
    let name: String
    let url: URL
}

enum TemplateEngine {
    private static let variableRegex = try! NSRegularExpression(pattern: "\\{\\{(title|date|time)(?::([^}]+))?\\}\\}")

    static func process(_ template: String, title: String, date: Date = Date()) -> String {
        let nsTemplate = template as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        var result = template

        let matches = variableRegex.matches(in: template, range: fullRange).reversed()
        for match in matches {
            let varName = nsTemplate.substring(with: match.range(at: 1))
            let format = match.range(at: 2).location != NSNotFound
                ? nsTemplate.substring(with: match.range(at: 2))
                : nil

            let replacement: String
            switch varName {
            case "title":
                replacement = title
            case "date":
                replacement = formatDate(date, format: format ?? "yyyy-MM-dd")
            case "time":
                replacement = formatDate(date, format: format ?? "HH:mm")
            default:
                continue
            }

            let range = Range(match.range(at: 0), in: result)!
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }

    static func loadTemplates(from folderURL: URL) -> [TemplateEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [TemplateEntry] = []
        let markdownExtensions: Set<String> = ["md", "markdown", "txt"]

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard markdownExtensions.contains(ext) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            entries.append(TemplateEntry(id: name, name: name, url: url))
        }

        return entries.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func formatDate(_ date: Date, format: String) -> String {
        let swiftFormat = momentToSwiftFormat(format)
        let formatter = DateFormatter()
        formatter.dateFormat = swiftFormat
        return formatter.string(from: date)
    }

    private static let momentMappings: [(String, String)] = [
        ("YYYY", "yyyy"),
        ("YY", "yy"),
        ("MMMM", "MMMM"),
        ("MMM", "MMM"),
        ("MM", "MM"),
        ("M", "M"),
        ("dddd", "EEEE"),
        ("ddd", "EEE"),
        ("DD", "dd"),
        ("D", "d"),
        ("HH", "HH"),
        ("H", "H"),
        ("hh", "hh"),
        ("h", "h"),
        ("mm", "mm"),
        ("m", "m"),
        ("ss", "ss"),
        ("s", "s"),
        ("A", "a"),
        ("a", "a"),
    ]

    private static func momentToSwiftFormat(_ format: String) -> String {
        var result = format
        for (moment, swift) in momentMappings {
            result = result.replacingOccurrences(of: moment, with: swift)
        }
        return result
    }
}
