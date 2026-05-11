import Foundation

@Observable
class VaultGraph {
    struct FileEntry {
        let name: String
        let url: URL
    }

    private(set) var files: [FileEntry] = []
    private var filesByName: [String: FileEntry] = [:]
    private var outLinks: [String: Set<String>] = [:]
    private var inLinks: [String: Set<String>] = [:]

    static let linkPattern = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")

    var sortedNames: [String] { files.map(\.name) }

    func build(from vaultURL: URL) {
        filesByName.removeAll()
        outLinks.removeAll()
        inLinks.removeAll()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            filesByName[name] = FileEntry(name: name, url: url)

            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let links = Self.parseLinks(from: content)
                outLinks[name] = links
                for link in links {
                    inLinks[link, default: []].insert(name)
                }
            }
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    struct SearchResult {
        let entry: FileEntry
        let highlights: [Range<String.Index>]
        let score: Double
    }

    func search(_ query: String) -> [FileEntry] {
        if query.isEmpty { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func fuzzySearch(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return files.map { SearchResult(entry: $0, highlights: [], score: 0) }
        }

        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return files.map { SearchResult(entry: $0, highlights: [], score: 0) }
        }

        var results: [SearchResult] = []

        for file in files {
            let name = file.name
            var ranges: [Range<String.Index>] = []
            var allFound = true

            for token in tokens {
                if let range = name.range(of: token, options: .caseInsensitive) {
                    ranges.append(range)
                } else {
                    allFound = false
                    break
                }
            }

            guard allFound else { continue }

            ranges.sort { $0.lowerBound < $1.lowerBound }
            let merged = Self.mergeRanges(ranges)

            let nameLen = Double(name.count)
            let matchedChars = merged.reduce(0.0) {
                $0 + Double(name.distance(from: $1.lowerBound, to: $1.upperBound))
            }
            let coverage = matchedChars / nameLen
            let brevity = 1.0 / (1.0 + nameLen / 20.0)
            let firstPos = merged.isEmpty ? nameLen : Double(name.distance(from: name.startIndex, to: merged.first!.lowerBound))
            let earlyBonus = 1.0 - firstPos / nameLen
            let score = coverage * 50 + brevity * 20 + earlyBonus * 30

            results.append(SearchResult(entry: file, highlights: merged, score: score))
        }

        return results.sorted { $0.score > $1.score }
    }

    private static func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        guard !ranges.isEmpty else { return [] }
        var merged = [ranges[0]]
        for range in ranges.dropFirst() {
            if range.lowerBound <= merged.last!.upperBound {
                let last = merged.removeLast()
                merged.append(last.lowerBound..<max(last.upperBound, range.upperBound))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    func url(for name: String) -> URL? {
        filesByName[name]?.url
    }

    func outgoing(from name: String) -> Set<String> {
        outLinks[name] ?? []
    }

    func incoming(to name: String) -> Set<String> {
        inLinks[name] ?? []
    }

    func addFile(name: String, url: URL) {
        let entry = FileEntry(name: name, url: url)
        filesByName[name] = entry
        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func rename(from oldName: String, to newName: String, newURL: URL) {
        guard let _ = filesByName.removeValue(forKey: oldName) else { return }
        filesByName[newName] = FileEntry(name: newName, url: newURL)

        if let links = outLinks.removeValue(forKey: oldName) {
            outLinks[newName] = links
            for link in links {
                inLinks[link]?.remove(oldName)
                inLinks[link, default: []].insert(newName)
            }
        }

        if let backrefs = inLinks.removeValue(forKey: oldName) {
            inLinks[newName] = backrefs
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func updateLinks(for name: String, content: String) {
        let oldLinks = outLinks[name] ?? []
        let newLinks = Self.parseLinks(from: content)
        guard oldLinks != newLinks else { return }

        for link in oldLinks where !newLinks.contains(link) {
            inLinks[link]?.remove(name)
        }
        for link in newLinks where !oldLinks.contains(link) {
            inLinks[link, default: []].insert(name)
        }
        outLinks[name] = newLinks
    }

    private static func parseLinks(from content: String) -> Set<String> {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        let matches = linkPattern.matches(in: content, range: range)
        var links = Set<String>()
        for match in matches {
            links.insert(nsContent.substring(with: match.range(at: 1)))
        }
        return links
    }
}
