import Foundation

final class SearchIndex: @unchecked Sendable {
    struct Result: Sendable {
        let name: String
        let url: URL
        let highlights: [Range<String.Index>]
        let score: Int
    }

    private nonisolated(unsafe) var names: [String] = []
    private nonisolated(unsafe) var urls: [URL] = []
    private nonisolated(unsafe) var bytes: [[UInt8]] = []

    nonisolated var count: Int { names.count }

    nonisolated func rebuild(from files: [VaultGraph.FileEntry]) {
        names = files.map(\.name)
        urls = files.map(\.url)
        bytes = names.map { Array($0.lowercased().utf8) }
    }

    nonisolated func search(_ query: String, limit: Int = 20) -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let n = min(limit, count)
            return (0..<n).map { Result(name: names[$0], url: urls[$0], highlights: [], score: 0) }
        }

        let queryBytes = Array(trimmed.lowercased().utf8).filter { $0 != 0x20 }
        guard !queryBytes.isEmpty else {
            let n = min(limit, count)
            return (0..<n).map { Result(name: names[$0], url: urls[$0], highlights: [], score: 0) }
        }

        var scored: [(Int, Int)] = []

        queryBytes.withUnsafeBufferPointer { qBuf in
            for i in 0..<bytes.count {
                bytes[i].withUnsafeBufferPointer { sBuf in
                    if let score = Self.fuzzyScore(pattern: qBuf, str: sBuf) {
                        scored.append((i, score))
                    }
                }
            }
        }

        scored.sort { $0.1 > $1.1 }
        let top = scored.prefix(limit)

        return top.map { (idx, score) in
            let highlights = Self.highlightRanges(name: names[idx], queryBytes: queryBytes)
            return Result(name: names[idx], url: urls[idx], highlights: highlights, score: score)
        }
    }

    private nonisolated static func fuzzyScore(
        pattern: UnsafeBufferPointer<UInt8>,
        str: UnsafeBufferPointer<UInt8>
    ) -> Int? {
        let pLen = pattern.count
        let sLen = str.count
        guard pLen > 0, pLen <= sLen else { return pLen == 0 ? 0 : nil }

        let p = pattern.baseAddress!
        let s = str.baseAddress!

        // Quick rejection: check all pattern chars exist in order
        var si = 0
        for pi in 0..<pLen {
            let target = p[pi]
            while si < sLen && s[si] != target { si += 1 }
            if si >= sLen { return nil }
            si += 1
        }

        // Greedy forward match to find positions
        var positions = [Int](repeating: 0, count: pLen)
        si = 0
        for pi in 0..<pLen {
            let target = p[pi]
            while s[si] != target { si += 1 }
            positions[pi] = si
            si += 1
        }

        // Score the match
        var score = 100

        for i in 0..<pLen {
            let pos = positions[i]

            if i > 0 && pos == positions[i - 1] + 1 {
                score += 15 // consecutive match
            }

            if pos == 0 {
                score += 30 // first character
            } else {
                let prev = s[pos - 1]
                if prev == 0x20 || prev == 0x5F || prev == 0x2D || prev == 0x2E {
                    score += 25 // word boundary
                }
            }
        }

        // leading gap penalty
        score -= min(positions[0] * 3, 15)

        // total gap penalty
        if pLen > 1 {
            let span = positions[pLen - 1] - positions[0] + 1
            score -= (span - pLen)
        }

        // shorter names are better matches
        score -= sLen

        return score
    }

    private nonisolated static func highlightRanges(name: String, queryBytes: [UInt8]) -> [Range<String.Index>] {
        guard !queryBytes.isEmpty else { return [] }

        let lower = name.lowercased()
        var indices: [String.Index] = []
        var searchFrom = lower.startIndex

        for qByte in queryBytes {
            let qChar = Character(UnicodeScalar(qByte))
            guard let idx = lower[searchFrom...].firstIndex(of: qChar) else { return [] }
            let offset = lower.distance(from: lower.startIndex, to: idx)
            indices.append(name.index(name.startIndex, offsetBy: offset))
            searchFrom = lower.index(after: idx)
        }

        var ranges: [Range<String.Index>] = []
        var start = indices[0]
        var prev = indices[0]

        for i in 1..<indices.count {
            let next = name.index(after: prev)
            if indices[i] == next {
                prev = indices[i]
            } else {
                ranges.append(start..<name.index(after: prev))
                start = indices[i]
                prev = indices[i]
            }
        }
        ranges.append(start..<name.index(after: prev))

        return ranges
    }
}
