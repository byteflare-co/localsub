# ADR-001: Native macOS-first product

Status: accepted for v1

## Decision

Build a SwiftUI desktop application and Swift CLI sharing Swift Package core modules.
Target Apple Silicon and macOS 26 or later. Use AVFoundation as the initial media boundary.

## Consequences

- Apple Speech and Translation integrate without a Python runtime or cloud service.
- Preview, permissions, cancellation, and native file panels fit the product workflow.
- v1 does not support Windows, Linux, Intel Macs, WebM, or arbitrary codecs.
- A future FFmpeg adapter remains possible without changing core project data.
