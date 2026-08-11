import Foundation

public struct PlannedTranslation: Sendable, Hashable {
    public let request: TranslationRequest
    public let range: RationalTimeRange

    public init(request: TranslationRequest, range: RationalTimeRange) {
        self.request = request
        self.range = range
    }
}

public struct TranslationPlanner: Sendable {
    public let maxGapSeconds: Double
    public let maxDurationSeconds: Double
    public let maxCharacters: Int
    public let preferredDurationSeconds: Double

    public init(
        maxGapSeconds: Double = 1.2,
        maxDurationSeconds: Double = 12,
        maxCharacters: Int = 300,
        preferredDurationSeconds: Double = 8
    ) {
        self.maxGapSeconds = maxGapSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.maxCharacters = maxCharacters
        if preferredDurationSeconds.isFinite {
            let upperBound = maxDurationSeconds.isFinite ? max(maxDurationSeconds, 0) : 0
            self.preferredDurationSeconds = min(max(preferredDurationSeconds, 0), upperBound)
        } else {
            self.preferredDurationSeconds = 0
        }
    }

    public func plan(_ spans: [TimedText]) throws -> [PlannedTranslation] {
        var output: [PlannedTranslation] = []
        var group: [(sourceID: String, span: TimedText)] = []

        func joinedText(_ items: [(sourceID: String, span: TimedText)]) -> String {
            items.map { $0.span.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        func makeUnit(_ items: [(sourceID: String, span: TimedText)], unitIndex: Int) throws -> PlannedTranslation? {
            guard let first = items.first, let last = items.last else { return nil }
            let text = joinedText(items)
            guard !text.isEmpty else { return nil }
            let ids = items.map(\.sourceID)
            return PlannedTranslation(
                request: TranslationRequest(id: "unit-\(unitIndex)", sourceSpanIDs: ids, text: text),
                range: try RationalTimeRange(start: first.span.range.start, end: last.span.range.end)
            )
        }

        var expanded: [(sourceID: String, span: TimedText)] = []
        for (index, span) in spans.enumerated() {
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let chunks = split(trimmed, maximumCharacters: maxCharacters)
            let totalCharacters = chunks.reduce(0) { $0 + $1.count }
            var consumedCharacters = 0
            for (chunkIndex, chunk) in chunks.enumerated() {
                let start = try interpolatedTime(
                    in: span.range,
                    consumedCharacters: consumedCharacters,
                    totalCharacters: totalCharacters
                )
                consumedCharacters += chunk.count
                let end = chunkIndex == chunks.count - 1
                    ? span.range.end
                    : try interpolatedTime(
                        in: span.range,
                        consumedCharacters: consumedCharacters,
                        totalCharacters: totalCharacters
                    )
                expanded.append((
                    sourceID: chunks.count == 1 ? "segment-\(index)" : "segment-\(index)-part-\(chunkIndex)",
                    span: TimedText(text: chunk, range: try RationalTimeRange(start: start, end: end))
                ))
            }
        }

        for item in expanded {
            let span = item.span
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = group.first, let previous = group.last {
                let gap = span.range.start.secondsDouble - previous.span.range.end.secondsDouble
                let proposedText = joinedText(group) + " " + trimmed
                let proposedDuration = span.range.end.secondsDouble - first.span.range.start.secondsDouble
                if gap > maxGapSeconds || proposedDuration > maxDurationSeconds || proposedText.count > maxCharacters {
                    if let unit = try makeUnit(group, unitIndex: output.count) { output.append(unit) }
                    group.removeAll(keepingCapacity: true)
                }
            }
            group.append(item)
            if trimmed.last.map({ ".!?。！？".contains($0) }) == true {
                let groupedDuration = span.range.end.secondsDouble
                    - (group.first?.span.range.start.secondsDouble ?? span.range.start.secondsDouble)
                if groupedDuration >= preferredDurationSeconds {
                    if let unit = try makeUnit(group, unitIndex: output.count) { output.append(unit) }
                    group.removeAll(keepingCapacity: true)
                }
            }
        }
        if let unit = try makeUnit(group, unitIndex: output.count) { output.append(unit) }
        return output
    }

    private func split(_ text: String, maximumCharacters: Int) -> [String] {
        precondition(maximumCharacters > 0)
        var chunks: [String] = []
        var current = ""
        for wordSlice in text.split(whereSeparator: \.isWhitespace) {
            var word = String(wordSlice)
            while word.count > maximumCharacters {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                let boundary = word.index(word.startIndex, offsetBy: maximumCharacters)
                chunks.append(String(word[..<boundary]))
                word = String(word[boundary...])
            }
            guard !word.isEmpty else { continue }
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= maximumCharacters {
                current += " " + word
            } else {
                chunks.append(current)
                current = word
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func interpolatedTime(
        in range: RationalTimeRange,
        consumedCharacters: Int,
        totalCharacters: Int
    ) throws -> RationalTime {
        if consumedCharacters == 0 { return range.start }
        if consumedCharacters == totalCharacters { return range.end }
        let scale = 1_000_000_000.0
        let seconds = range.start.secondsDouble
            + range.durationSeconds * Double(consumedCharacters) / Double(totalCharacters)
        return try RationalTime(value: Int64((seconds * scale).rounded()), timescale: Int32(1_000_000_000))
    }
}
