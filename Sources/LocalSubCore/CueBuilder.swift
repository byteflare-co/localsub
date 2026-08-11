import Foundation
import NaturalLanguage

public struct CuePolicy: Sendable, Hashable {
    public let maxLineHalfUnits: Int
    public let maxLines: Int
    public let maxReadingUnitsPerSecond: Double

    public init(maxLineHalfUnits: Int, maxLines: Int, maxReadingUnitsPerSecond: Double) {
        self.maxLineHalfUnits = maxLineHalfUnits
        self.maxLines = maxLines
        self.maxReadingUnitsPerSecond = maxReadingUnitsPerSecond
    }

    public static let defaultJapanese = CuePolicy(
        maxLineHalfUnits: 48,
        maxLines: 2,
        maxReadingUnitsPerSecond: 7
    )
}

public struct CueBuilder: Sendable {
    private struct NaturalBoundary {
        let index: String.Index
        let precedingToken: String
        let precedingCharacter: String
        let prefixHalfUnits: Int
    }

    public let policy: CuePolicy
    public let protectedTerms: [String]
    private let protectedTermsByFirstCharacter: [Character: [String]]

    public init(policy: CuePolicy, protectedTerms: [String] = []) {
        self.policy = policy
        let terms = protectedTerms.filter { !$0.isEmpty }
        self.protectedTerms = terms
        self.protectedTermsByFirstCharacter = Dictionary(grouping: terms, by: { $0.first! })
    }

    public func build(from inputs: [TimedText]) throws -> [DisplayCue] {
        var output: [DisplayCue] = []
        var nextID = 1
        for input in inputs {
            let normalized = input.text.replacingOccurrences(of: "\r\n", with: "\n")
            guard !normalized.isEmpty else { continue }
            let chunks = chunk(normalized, maximumHalfUnits: policy.maxLineHalfUnits * policy.maxLines)
            let totalWeight = max(chunks.reduce(0) { $0 + halfUnits(in: $1) }, 1)
            var accumulatedWeight = 0
            let startMS = try input.range.start.srtMilliseconds()
            let endMS = try input.range.end.srtMilliseconds()
            let durationMS = max(endMS - startMS, Int64(chunks.count))

            for (index, chunk) in chunks.enumerated() {
                let weight = max(halfUnits(in: chunk), 1)
                let chunkStart = startMS + durationMS * Int64(accumulatedWeight) / Int64(totalWeight)
                accumulatedWeight += weight
                var chunkEnd = index == chunks.count - 1
                    ? endMS
                    : startMS + durationMS * Int64(accumulatedWeight) / Int64(totalWeight)
                if chunkEnd <= chunkStart { chunkEnd = chunkStart + 1 }
                let range = try RationalTimeRange(start: .milliseconds(chunkStart), end: .milliseconds(chunkEnd))
                let formatted = wrap(chunk)
                let readingUnits = Double(halfUnits(in: chunk)) / 2.0 / max(range.durationSeconds, 0.001)
                let warnings: Set<CueWarning> = readingUnits > policy.maxReadingUnitsPerSecond
                    ? [.readingSpeedExceeded]
                    : []
                output.append(try DisplayCue.validated(
                    id: "cue-\(nextID)", text: formatted, range: range, warnings: warnings
                ))
                nextID += 1
            }
        }
        try CaptionProject.validateDisplayCues(output)
        return output
    }

    private func chunk(_ text: String, maximumHalfUnits: Int) -> [String] {
        splitNaturally(text, maximumHalfUnits: maximumHalfUnits)
    }

    private func wrap(_ text: String) -> String {
        guard halfUnits(in: text) > policy.maxLineHalfUnits else { return text }
        let protectedInteriorBoundaries = protectedInteriorBoundaries(in: text)
        let pieces = splitNaturally(
            text,
            maximumHalfUnits: policy.maxLineHalfUnits,
            protectedInteriorBoundaries: protectedInteriorBoundaries
        )
        if pieces.count <= 2 { return pieces.joined(separator: "\n") }

        // Japanese word boundaries can sit several half-width units away from the
        // geometric midpoint. Keep a small visual overflow budget so a compound such
        // as 「手順」 is not cut merely to make both lines exactly equal.
        let tolerance = policy.maxLineHalfUnits / 4
        let prefixWidths = prefixHalfUnitWidths(in: text)
        let totalWidth = prefixWidths[text.endIndex] ?? halfUnits(in: text)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var balanced: [String.Index] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let left = prefixWidths[range.upperBound] ?? 0
            let right = totalWidth - left
            if left <= policy.maxLineHalfUnits + tolerance,
               right <= policy.maxLineHalfUnits + tolerance,
               range.upperBound < text.endIndex,
               isSafeBoundary(range.upperBound, in: text, protectedInteriorBoundaries: protectedInteriorBoundaries) {
                balanced.append(range.upperBound)
            }
            return true
        }
        if let boundary = balanced.min(by: {
            let left0 = prefixWidths[$0] ?? 0
            let left1 = prefixWidths[$1] ?? 0
            let maxSide0 = max(left0, totalWidth - left0)
            let maxSide1 = max(left1, totalWidth - left1)
            if maxSide0 != maxSide1 { return maxSide0 < maxSide1 }
            return abs(left0 - (totalWidth - left0)) < abs(left1 - (totalWidth - left1))
        }) {
            return String(text[..<boundary]) + "\n" + String(text[boundary...])
        }
        let boundary = hardBoundary(
            from: text.startIndex,
            in: text,
            maximumHalfUnits: policy.maxLineHalfUnits,
            protectedInteriorBoundaries: protectedInteriorBoundaries
        )
        return String(text[..<boundary]) + "\n" + String(text[boundary...])
    }

    private func splitNaturally(
        _ text: String,
        maximumHalfUnits: Int,
        protectedInteriorBoundaries suppliedProtectedInteriorBoundaries: Set<String.Index>? = nil
    ) -> [String] {
        guard !text.isEmpty else { return [] }
        let protectedInteriorBoundaries = suppliedProtectedInteriorBoundaries ?? protectedInteriorBoundaries(in: text)
        let prefixWidths = prefixHalfUnitWidths(in: text)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokensByBoundary: [String.Index: String] = [:]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokensByBoundary[range.upperBound] = String(text[range])
            return true
        }
        let punctuationBoundaries: Set<Character> = ["。", "！", "？", "!", "?", "、", ",", ";", "；", ":", "："]
        var boundaryIndices = Set(tokensByBoundary.keys)
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let next = text.index(after: cursor)
            if punctuationBoundaries.contains(text[cursor]) { boundaryIndices.insert(next) }
            cursor = next
        }
        boundaryIndices.insert(text.endIndex)
        let boundaries = boundaryIndices.sorted().map { index in
            NaturalBoundary(
                index: index,
                precedingToken: tokensByBoundary[index] ?? "",
                precedingCharacter: index > text.startIndex ? String(text[text.index(before: index)]) : "",
                prefixHalfUnits: prefixWidths[index] ?? 0
            )
        }

        var pieces: [String] = []
        var start = text.startIndex
        var startWidth = 0
        var searchOffset = 0
        while start < text.endIndex {
            while searchOffset < boundaries.count, boundaries[searchOffset].index <= start {
                searchOffset += 1
            }
            var candidates: [NaturalBoundary] = []
            var candidateOffset = searchOffset
            while candidateOffset < boundaries.count {
                let boundary = boundaries[candidateOffset]
                guard boundary.prefixHalfUnits - startWidth <= maximumHalfUnits else { break }
                candidates.append(boundary)
                candidateOffset += 1
            }
            let safeCandidates = candidates.filter {
                isSafeBoundary($0.index, in: text, protectedInteriorBoundaries: protectedInteriorBoundaries)
            }
            let selectedBoundary = safeCandidates.max(by: {
                boundaryScore($0, startWidth: startWidth, maximumHalfUnits: maximumHalfUnits)
                    < boundaryScore($1, startWidth: startWidth, maximumHalfUnits: maximumHalfUnits)
            }) ?? candidates.last
            let end = selectedBoundary?.index
                ?? hardBoundary(
                    from: start,
                    in: text,
                    maximumHalfUnits: maximumHalfUnits,
                    protectedInteriorBoundaries: protectedInteriorBoundaries
                )
            pieces.append(String(text[start..<end]))
            start = end
            startWidth = prefixWidths[end] ?? startWidth + halfUnits(in: pieces.last ?? "")
        }
        return pieces
    }

    private func boundaryScore(
        _ boundary: NaturalBoundary,
        startWidth: Int,
        maximumHalfUnits: Int
    ) -> Int {
        let width = boundary.prefixHalfUnits - startWidth
        let sentenceTerminators: Set<String> = ["。", "！", "？", "!", "?"]
        let clausePunctuation: Set<String> = ["、", ",", ";", "；", ":", "："]
        let completedExpressions: Set<String> = [
            "です", "ます", "でした", "ました", "ません", "ましょう", "でしょう", "ください",
        ]
        let dependentParticles: Set<String> = [
            "の", "を", "に", "へ", "と", "が", "は", "で", "も", "や", "お", "ご", "御",
        ]

        if sentenceTerminators.contains(boundary.precedingCharacter), width >= maximumHalfUnits / 4 {
            // Never consume the start of a new sentence merely to fill the visual box.
            return width + maximumHalfUnits * 4
        }
        if clausePunctuation.contains(boundary.precedingCharacter) {
            return width + maximumHalfUnits / 2
        }
        if completedExpressions.contains(boundary.precedingToken) {
            return width + maximumHalfUnits / 3
        }
        if dependentParticles.contains(boundary.precedingToken) {
            return width - maximumHalfUnits
        }
        return width
    }

    private func prefixHalfUnitWidths(in text: String) -> [String.Index: Int] {
        var result: [String.Index: Int] = [text.startIndex: 0]
        var cursor = text.startIndex
        var width = 0
        while cursor < text.endIndex {
            let next = text.index(after: cursor)
            width += halfUnits(in: String(text[cursor..<next]))
            result[next] = width
            cursor = next
        }
        return result
    }

    private func isSafeBoundary(
        _ index: String.Index,
        in text: String,
        protectedInteriorBoundaries: Set<String.Index>
    ) -> Bool {
        guard index < text.endIndex else { return true }
        guard !protectedInteriorBoundaries.contains(index) else { return false }
        let remainder = text[index...]
        let unsafeStarts = [
            "でした", "ません", "ます", "です", "ない", "ので", "から", "けれど", "ため",
            "は", "が", "を", "に", "へ", "で", "と", "も", "の", "や", "ね", "よ", "か",
            "、", "。", "！", "？", ",", ".", "!", "?",
        ]
        return !unsafeStarts.contains { remainder.hasPrefix($0) }
    }

    private func protectedInteriorBoundaries(in text: String) -> Set<String.Index> {
        var result: Set<String.Index> = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if let possibleTerms = protectedTermsByFirstCharacter[text[cursor]] {
                for term in possibleTerms where text[cursor...].hasPrefix(term) {
                    let upperBound = text.index(cursor, offsetBy: term.count)
                    var boundary = text.index(after: cursor)
                    while boundary < upperBound {
                        result.insert(boundary)
                        boundary = text.index(after: boundary)
                    }
                }
            }
            cursor = text.index(after: cursor)
        }
        return result
    }

    private func hardBoundary(
        from start: String.Index,
        in text: String,
        maximumHalfUnits: Int,
        protectedInteriorBoundaries: Set<String.Index>
    ) -> String.Index {
        var end = start
        var width = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            let characterWidth = halfUnits(in: String(text[end..<next]))
            if end > start && width + characterWidth > maximumHalfUnits { break }
            width += characterWidth
            end = next
        }
        var adjusted = end
        while adjusted > start, adjusted < text.endIndex,
              protectedInteriorBoundaries.contains(adjusted) {
            adjusted = text.index(before: adjusted)
        }
        while adjusted > start, adjusted < text.endIndex {
            let previous = text.index(before: adjusted)
            guard isLatinWordCharacter(text[previous]), isLatinWordCharacter(text[adjusted]) else { break }
            adjusted = previous
        }
        if adjusted > start { return adjusted }
        return end == start ? text.index(after: start) : end
    }

    private func isLatinWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57)
                || ($0.value >= 65 && $0.value <= 90)
                || ($0.value >= 97 && $0.value <= 122)
                || $0 == "_" || $0 == "-"
        }
    }

    private func halfUnits(in text: String) -> Int {
        text.unicodeScalars.reduce(0) { result, scalar in
            if scalar == "\n" { return result }
            return result + (scalar.value <= 0x7F ? 1 : 2)
        }
    }
}
