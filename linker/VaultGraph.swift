import Foundation

struct Reference {
    let line: Int
    let column: Int
    let filename: String
}

@Observable
class VaultGraph {
    struct FileEntry {
        let name: String
        let url: URL
    }

    private(set) var files: [FileEntry] = []
    private(set) var fileNameSet: Set<String> = []
    private(set) var references: [String: [Reference]] = [:]
    private var filesByName: [String: FileEntry] = [:]
    private var indexedModDates: [String: Date] = [:]

    func build(from vaultURL: URL) {
        filesByName.removeAll()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "md" {
                let name = url.deletingPathExtension().lastPathComponent
                filesByName[name] = FileEntry(name: name, url: url)
            }
        }

        files = filesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        fileNameSet = Set(filesByName.keys)
        buildReferences()
    }

    private func buildReferences() {
        let currentNames = Set(filesByName.keys)
        for stale in indexedModDates.keys where !currentNames.contains(stale) {
            indexedModDates.removeValue(forKey: stale)
            references.removeValue(forKey: stale)
        }

        var changed = false
        for entry in files {
            let modDate = (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modDate, indexedModDates[entry.name] == modDate {
                continue
            }
            indexedModDates[entry.name] = modDate
            parseReferences(name: entry.name, url: entry.url)
            changed = true
        }

        if changed {
            // trigger observation by reassigning
            references = references
        }
    }

    func search(_ query: String, limit: Int = 20) -> [FileEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return Array(files.prefix(limit))
        }
        var results: [FileEntry] = []
        for file in files {
            if file.name.lowercased().contains(trimmed) {
                results.append(file)
                if results.count >= limit { break }
            }
        }
        return results
    }

    func url(for name: String) -> URL? {
        filesByName[name]?.url
    }

    func outgoingReferences(for filename: String) -> [Reference] {
        references[filename] ?? []
    }

    func incomingReferences(for filename: String) -> [(source: String, reference: Reference)] {
        var result: [(source: String, reference: Reference)] = []
        for (source, refs) in references {
            for ref in refs where ref.filename == filename {
                result.append((source: source, reference: ref))
            }
        }
        return result.sorted { $0.source.localizedCompare($1.source) == .orderedAscending }
    }

    func addFile(name: String, url: URL) {
        let entry = FileEntry(name: name, url: url)
        filesByName[name] = entry
        fileNameSet.insert(name)
        let idx = files.firstIndex { name.localizedCompare($0.name) == .orderedAscending } ?? files.endIndex
        files.insert(entry, at: idx)
        indexFile(name: name, url: url)
    }

    func indexFile(name: String, url: URL) {
        indexedModDates[name] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        parseReferences(name: name, url: url)
    }

    private static let wikiLinkRegex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")

    private static func buildLineOffsets(for string: NSString) -> [Int] {
        var offsets = [0]
        for i in 0..<string.length {
            if string.character(at: i) == 0x0A {
                offsets.append(i + 1)
            }
        }
        return offsets
    }

    private static func lineAndColumn(at location: Int, lineOffsets: [Int]) -> (line: Int, column: Int) {
        var low = 0, high = lineOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineOffsets[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return (line: low + 1, column: location - lineOffsets[low] + 1)
    }

    private func parseReferences(name: String, url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            references.removeValue(forKey: name)
            return
        }
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let lineOffsets = Self.buildLineOffsets(for: nsContent)
        var refs: [Reference] = []
        for match in Self.wikiLinkRegex.matches(in: content, range: fullRange) {
            let target = nsContent.substring(with: match.range(at: 1))
            let pos = Self.lineAndColumn(at: match.range(at: 0).location, lineOffsets: lineOffsets)
            refs.append(Reference(line: pos.line, column: pos.column, filename: target))
        }
        references[name] = refs.isEmpty ? nil : refs
    }
}
