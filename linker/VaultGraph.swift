import Foundation

@Observable
class VaultGraph {
    struct FileEntry {
        let name: String
        let url: URL
    }

    private(set) var files: [FileEntry] = []
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

    func addFile(name: String, url: URL) {
        let entry = FileEntry(name: name, url: url)
        filesByName[name] = entry
        let idx = files.firstIndex { name.localizedCompare($0.name) == .orderedAscending } ?? files.endIndex
        files.insert(entry, at: idx)
    }
}
