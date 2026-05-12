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

    nonisolated func search(_ query: String, limit: Int = 20, cancelled: () -> Bool = { false }) -> [Result] {
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
        scored.reserveCapacity(min(bytes.count, 1000))

        let fileCount = bytes.count
        queryBytes.withUnsafeBufferPointer { qBuf in
            for i in 0..<fileCount {
                if i & 0xFF == 0 && cancelled() { return }
                bytes[i].withUnsafeBufferPointer { sBuf in
                    if let score = Self.fuzzyScore(pattern: qBuf, str: sBuf) {
                        scored.append((i, score))
                    }
                }
            }
        }

        if cancelled() { return [] }

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

        // Try contiguous substring match first
        var contiguousStart = -1
        for start in 0...(sLen - pLen) {
            var match = true
            for j in 0..<pLen {
                if s[start + j] != p[j] { match = false; break }
            }
            if match { contiguousStart = start; break }
        }

        // Score the match
        var score = 100

        if contiguousStart >= 0 {
            score += 100
            if contiguousStart == 0 {
                score += 60
            } else {
                let prev = s[contiguousStart - 1]
                if prev == 0x20 || prev == 0x5F || prev == 0x2D || prev == 0x2E {
                    score += 50
                }
            }
            let endPos = contiguousStart + pLen
            if endPos == sLen || (endPos < sLen && {
                let next = s[endPos]
                return next == 0x20 || next == 0x5F || next == 0x2D || next == 0x2E
            }()) {
                score += 20
            }
            if pLen == sLen {
                score += 80
            }
            score -= min(contiguousStart * 3, 15)
        } else {
            // Greedy forward match — no heap allocation, use inline scoring
            si = 0
            var prevPos = -1
            var firstPos = 0
            var lastPos = 0
            for pi in 0..<pLen {
                let target = p[pi]
                while s[si] != target { si += 1 }
                let pos = si

                if pi == 0 { firstPos = pos }
                lastPos = pos

                if pi > 0 && pos == prevPos + 1 {
                    score += 15
                }
                if pos == 0 {
                    score += 30
                } else {
                    let prev = s[pos - 1]
                    if prev == 0x20 || prev == 0x5F || prev == 0x2D || prev == 0x2E {
                        score += 25
                    }
                }

                prevPos = pos
                si += 1
            }

            let span = lastPos - firstPos + 1
            score -= (span - pLen) * 2
            score -= min(firstPos * 3, 15)
        }

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
