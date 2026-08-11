# ADR-004: AVFoundation rendering first, FFmpeg later

Status: accepted for v1

## Decision

Use AVFoundation/Core Animation for the initial MOV/MP4 SDR slice. Add FFmpeg only when
broader format support justifies its binary distribution, sandbox, and license obligations.

## Consequences

- The initial dependency and license surface stays small.
- Input codec support is intentionally narrower.
- Preview/export layout parity requires one shared layout engine and rendering fixtures.
- An FFmpeg adapter must remain isolated and may not invoke a shell.
