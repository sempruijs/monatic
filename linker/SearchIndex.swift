import Foundation

final class SearchIndex {
    struct Result {
        let name: String
        let url: URL
        let highlights: [Range<String.Index>]
        let score: Double
    }

    private var names: [String] = []
    private var urls: [URL] = []
    private var bytes: [[UInt8]] = []

    var count: Int { names.count }

    func rebuild(from files: [VaultGraph.FileEntry]) {
        let n = files.count
        names = [String](repeating: "", count: n)
        urls = [URL](repeating: URL(fileURLWithPath: "/"), count: n)
        bytes = [[UInt8]](repeating: [], count: n)
        for i in 0..<n {
            names[i] = files[i].name
            urls[i] = files[i].url
            bytes[i] = Array(files[i].name.lowercased().utf8)
        }
    }

    func search(_ query: String, limit: Int = 20) -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let n = min(limit, count)
            return (0..<n).map { Result(name: names[$0], url: urls[$0], highlights: [], score: 0) }
        }

        let tokenBytes: [[UInt8]] = trimmed.lowercased()
            .split(separator: " ")
            .map { Array($0.utf8) }
        guard !tokenBytes.isEmpty else {
            let n = min(limit, count)
            return (0..<n).map { Result(name: names[$0], url: urls[$0], highlights: [], score: 0) }
        }

        var scored: [(Int, Double)] = []

        for i in 0..<bytes.count {
            let hay = bytes[i]
            let hayLen = hay.count
            guard hayLen > 0 else { continue }

            var totalMatch = 0
            var firstPos = hayLen
            var found = true

            for token in tokenBytes {
                guard let pos = Self.find(hay: hay, needle: token) else {
                    found = false
                    break
                }
                totalMatch += token.count
                if pos < firstPos { firstPos = pos }
            }

            guard found else { continue }

            let len = Double(hayLen)
            let score = Double(totalMatch) / len * 50.0
                      + 1.0 / (1.0 + len / 20.0) * 20.0
                      + (1.0 - Double(firstPos) / len) * 30.0
            scored.append((i, score))
        }

        scored.sort { $0.1 > $1.1 }

        let top = scored.prefix(limit)
        let stringTokens = trimmed.split(separator: " ").map(String.init)

        return top.map { (idx, score) in
            let highlights = Self.highlights(in: names[idx], tokens: stringTokens)
            return Result(name: names[idx], url: urls[idx], highlights: highlights, score: score)
        }
    }

    private static func find(hay: [UInt8], needle: [UInt8]) -> Int? {
        let n = hay.count
        let m = needle.count
        guard m > 0, m <= n else { return m == 0 ? 0 : nil }

        return hay.withUnsafeBufferPointer { hBuf in
            needle.withUnsafeBufferPointer { pBuf in
                let h = hBuf.baseAddress!
                let p = pBuf.baseAddress!
                let first = p[0]
                let limit = n - m

                var i = 0
                while i <= limit {
                    if h[i] == first {
                        if m == 1 || memcmp(h + i + 1, p + 1, m - 1) == 0 {
                            return i
                        }
                    }
                    i += 1
                }
                return nil
            }
        }
    }

    private static func highlights(in name: String, tokens: [String]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            if let r = name.range(of: token, options: .caseInsensitive) {
                ranges.append(r)
            }
        }
        guard ranges.count > 1 else { return ranges }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged = [ranges[0]]
        for r in ranges.dropFirst() {
            if r.lowerBound <= merged[merged.count - 1].upperBound {
                let prev = merged.removeLast()
                merged.append(prev.lowerBound..<max(prev.upperBound, r.upperBound))
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
