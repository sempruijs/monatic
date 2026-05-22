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

    struct SearchResult: Identifiable {
        let id: String
        let name: String
        let url: URL
        let score: Int
    }

    private struct IndexedName {
        let name: String
        let scalars: [UInt32]
        let url: URL
    }

    private(set) var files: [FileEntry] = []
    private(set) var fileNameSet: Set<String> = []
    private(set) var references: [String: [Reference]] = [:]
    private(set) var recentFiles: [FileEntry] = []
    private var markdownByName: [String: FileEntry] = [:]
    private var allFilesByName: [String: FileEntry] = [:]
    private var indexedModDates: [String: Date] = [:]
    private var searchIndex: [IndexedName] = []
    private static let maxRecents = 10
    private static let markdownExtensions: Set<String> = ["md", "markdown", "txt"]

    func build(from vaultURL: URL) {
        markdownByName.removeAll()
        allFilesByName.removeAll()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            let displayName = url.lastPathComponent
            let entry = FileEntry(name: displayName, url: url)
            allFilesByName[displayName] = entry

            if Self.markdownExtensions.contains(ext) {
                let baseName = url.deletingPathExtension().lastPathComponent
                markdownByName[baseName] = entry
            }
        }

        files = allFilesByName.values.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        fileNameSet = Set(markdownByName.keys)
        rebuildSearchIndex()
        buildReferences()
    }

    private func buildReferences() {
        let currentNames = Set(markdownByName.keys)
        for stale in indexedModDates.keys where !currentNames.contains(stale) {
            indexedModDates.removeValue(forKey: stale)
            references.removeValue(forKey: stale)
        }

        var changed = false
        for (name, entry) in markdownByName {
            let modDate = (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modDate, indexedModDates[name] == modDate {
                continue
            }
            indexedModDates[name] = modDate
            parseReferences(name: name, url: entry.url)
            changed = true
        }

        if changed {
            // trigger observation by reassigning
            references = references
        }
    }

    func recordVisit(_ url: URL) {
        let displayName = url.lastPathComponent
        recentFiles.removeAll { $0.name == displayName }
        if let entry = allFilesByName[displayName] {
            recentFiles.insert(entry, at: 0)
        }
        if recentFiles.count > Self.maxRecents {
            recentFiles.removeLast(recentFiles.count - Self.maxRecents)
        }
    }

    func search(_ query: String, limit: Int = 20) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let source = recentFiles.isEmpty ? Array(files.prefix(limit)) : recentFiles
            return source.enumerated().map { i, f in
                SearchResult(id: f.name, name: f.name, url: f.url, score: source.count - i)
            }
        }
        let queryScalars = Array(trimmed.lowercased().unicodeScalars.map(\.value))
        var scored: [(index: Int, score: Int)] = []
        scored.reserveCapacity(min(searchIndex.count, limit * 2))
        for i in 0..<searchIndex.count {
            if let score = Self.fuzzyScore(query: queryScalars, candidate: searchIndex[i].scalars) {
                scored.append((i, score))
            }
        }
        scored.sort { $0.score > $1.score }
        let top = scored.prefix(limit)
        return top.map { item in
            let entry = searchIndex[item.index]
            return SearchResult(id: entry.name, name: entry.name, url: entry.url, score: item.score)
        }
    }

    private func rebuildSearchIndex() {
        searchIndex = files.map { entry in
            IndexedName(
                name: entry.name,
                scalars: Array(entry.name.lowercased().unicodeScalars.map(\.value)),
                url: entry.url
            )
        }
    }

    private static func fuzzyScore(query: [UInt32], candidate: [UInt32]) -> Int? {
        guard !query.isEmpty else { return 0 }
        guard candidate.count >= query.count else { return nil }

        var score = 0
        var qi = 0
        var consecutive = 0
        let isPrefix = candidate.count >= query.count
            && candidate[0..<query.count].elementsEqual(query)

        if isPrefix { score += 20 }

        for ci in 0..<candidate.count {
            guard qi < query.count else { break }
            if candidate[ci] == query[qi] {
                score += 1
                if consecutive > 0 { score += 3 }
                if ci == 0 { score += 10 }
                let isWordStart = ci > 0 && Self.isWordBoundary(candidate[ci - 1])
                if isWordStart { score += 5 }
                consecutive += 1
                qi += 1
            } else {
                consecutive = 0
            }
        }

        return qi == query.count ? score : nil
    }

    private static func isWordBoundary(_ scalar: UInt32) -> Bool {
        scalar == 0x20 || scalar == 0x2D || scalar == 0x5F || scalar == 0x2E
    }

    func url(for name: String) -> URL? {
        markdownByName[name]?.url
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

    func renameFile(oldName: String, newName: String, newURL: URL) {
        let oldDisplayName = oldName + ".md"
        let newDisplayName = newName + ".md"

        markdownByName.removeValue(forKey: oldName)
        allFilesByName.removeValue(forKey: oldDisplayName)
        fileNameSet.remove(oldName)
        files.removeAll { $0.name == oldDisplayName }

        let entry = FileEntry(name: newDisplayName, url: newURL)
        markdownByName[newName] = entry
        allFilesByName[newDisplayName] = entry
        fileNameSet.insert(newName)
        let idx = files.firstIndex { newDisplayName.localizedCompare($0.name) == .orderedAscending } ?? files.endIndex
        files.insert(entry, at: idx)

        if let refs = references.removeValue(forKey: oldName) {
            references[newName] = refs
        }
        indexedModDates.removeValue(forKey: oldName)
        indexedModDates[newName] = (try? newURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        if let i = recentFiles.firstIndex(where: { $0.name == oldDisplayName }) {
            recentFiles[i] = entry
        }

        searchIndex.removeAll { $0.name == oldDisplayName }
        searchIndex.append(IndexedName(
            name: newDisplayName,
            scalars: Array(newDisplayName.lowercased().unicodeScalars.map(\.value)),
            url: newURL
        ))
    }

    func addFile(name: String, url: URL) {
        let displayName = url.lastPathComponent
        let entry = FileEntry(name: displayName, url: url)
        let ext = url.pathExtension.lowercased()

        allFilesByName[displayName] = entry
        if Self.markdownExtensions.contains(ext) {
            markdownByName[name] = entry
            fileNameSet.insert(name)
        }

        let idx = files.firstIndex { displayName.localizedCompare($0.name) == .orderedAscending } ?? files.endIndex
        files.insert(entry, at: idx)
        searchIndex.append(IndexedName(
            name: displayName,
            scalars: Array(displayName.lowercased().unicodeScalars.map(\.value)),
            url: url
        ))

        if Self.markdownExtensions.contains(ext) {
            indexFile(name: name, url: url)
        }
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
