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
        var result: [String: [Reference]] = [:]
        let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        for entry in files {
            guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            let nsContent = content as NSString
            var refs: [Reference] = []
            for match in regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length)) {
                let innerRange = match.range(at: 1)
                let target = nsContent.substring(with: innerRange)
                let location = match.range(at: 0).location
                let lineRange = nsContent.lineRange(for: NSRange(location: location, length: 0))
                let lineStart = lineRange.location
                var lineNumber = 1
                var i = 0
                while i < location {
                    if nsContent.character(at: i) == 0x0A { lineNumber += 1 }
                    i += 1
                }
                let column = location - lineStart + 1
                refs.append(Reference(line: lineNumber, column: column, filename: target))
            }
            if !refs.isEmpty {
                result[entry.name] = refs
            }
        }
        references = result
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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let nsContent = content as NSString
        let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        var refs: [Reference] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length)) {
            let innerRange = match.range(at: 1)
            let target = nsContent.substring(with: innerRange)
            let location = match.range(at: 0).location
            let lineRange = nsContent.lineRange(for: NSRange(location: location, length: 0))
            let lineStart = lineRange.location
            var lineNumber = 1
            var i = 0
            while i < location {
                if nsContent.character(at: i) == 0x0A { lineNumber += 1 }
                i += 1
            }
            let column = location - lineStart + 1
            refs.append(Reference(line: lineNumber, column: column, filename: target))
        }
        references[name] = refs.isEmpty ? nil : refs
    }
}
