import Foundation

@Observable
class VaultGraph {
    struct FileEntry {
        let name: String
        let url: URL
    }

    private(set) var files: [FileEntry] = []
    private var filesByName: [String: FileEntry] = [:]
    private(set) var assetNames: Set<String> = []
    private var outLinks: [String: Set<String>] = [:]
    private var inLinks: [String: Set<String>] = [:]
    let searchIndex = SearchIndex()

    typealias SearchResult = SearchIndex.Result

    static let linkPattern = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
    private static let textExtensions: Set<String> = ["md", "markdown", "txt"]

    var sortedNames: [String] {
        (files.map(\.name) + assetNames.sorted()).sorted {
            $0.localizedCompare($1) == .orderedAscending
        }
    }

    func build(from vaultURL: URL) {
        filesByName.removeAll()
        assetNames.removeAll()
        outLinks.removeAll()
        inLinks.removeAll()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "md" {
                let name = url.deletingPathExtension().lastPathComponent
                filesByName[name] = FileEntry(name: name, url: url)

                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let links = Self.parseLinks(from: content)
                    outLinks[name] = links
                    for link in links {
                        inLinks[link, default: []].insert(name)
                    }
                }
            } else if !Self.textExtensions.contains(ext) && !ext.isEmpty {
                assetNames.insert(url.lastPathComponent)
            }
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        searchIndex.rebuild(from: files)
    }

    func fuzzySearch(_ query: String, limit: Int = 20) -> [SearchResult] {
        searchIndex.search(query, limit: limit)
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

    func updateReferences(from oldName: String, to newName: String) {
        let referrers = inLinks[newName] ?? inLinks[oldName] ?? []
        for referrer in referrers {
            guard let entry = filesByName[referrer] else { continue }
            guard var content = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            content = content.replacingOccurrences(of: "[[\(oldName)]]", with: "[[\(newName)]]")
            try? content.write(to: entry.url, atomically: true, encoding: .utf8)
            let newLinks = Self.parseLinks(from: content)
            outLinks[referrer] = newLinks
        }
    }

    func addFile(name: String, url: URL) {
        let entry = FileEntry(name: name, url: url)
        filesByName[name] = entry
        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        searchIndex.rebuild(from: files)
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
        searchIndex.rebuild(from: files)
    }

    func removeFile(name: String) {
        filesByName.removeValue(forKey: name)

        if let links = outLinks.removeValue(forKey: name) {
            for link in links {
                inLinks[link]?.remove(name)
            }
        }

        inLinks.removeValue(forKey: name)

        for (source, _) in outLinks where outLinks[source]?.contains(name) == true {
            outLinks[source]?.remove(name)
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        searchIndex.rebuild(from: files)
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
