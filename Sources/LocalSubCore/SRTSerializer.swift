import Foundation

public enum SRTSerializer {
    public static func serialize(_ cues: [DisplayCue]) throws -> String {
        try CaptionProject.validateDisplayCues(cues)
        var blocks: [String] = []
        for (index, cue) in cues.enumerated() {
            let start = try timestamp(cue.range.start.srtMilliseconds())
            let end = try timestamp(cue.range.end.srtMilliseconds())
            blocks.append("\(index + 1)\n\(start) --> \(end)\n\(cue.text)")
        }
        return blocks.joined(separator: "\n\n") + (blocks.isEmpty ? "" : "\n")
    }

    private static func timestamp(_ milliseconds: Int64) throws -> String {
        guard milliseconds >= 0 else { throw LocalSubError.invalidTime }
        let hours = milliseconds / 3_600_000
        let minutes = milliseconds / 60_000 % 60
        let seconds = milliseconds / 1_000 % 60
        let millis = milliseconds % 1_000
        return String(format: "%02lld:%02lld:%02lld,%03lld", hours, minutes, seconds, millis)
    }
}
