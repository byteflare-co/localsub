# ADR-005: Sandboxed Developer ID desktop distribution

Status: accepted for v1 dogfood and release candidate

## Decision

The shipped desktop app uses App Sandbox and Hardened Runtime even when distributed outside
the Mac App Store. It receives only user-selected read-only input/project access and
user-selected read-write file access because one process handles both Open and Save panels;
application code never opens the selected input for writing. All Files access, temporary exception entitlements,
JIT, unsigned executable memory, disabled library validation, and DYLD environment entitlement
exceptions are prohibited.

Developer ID builds must be signed, notarized, and stapled. CI/release verification records
the resolved entitlements and validates the artifact with `codesign` and `spctl`. The CLI is
development-only for v1 and is not embedded in the distributed application.

## Model network boundary

The initial no-network decision is superseded for optional GPT-5.6 Luna translation by
[ADR-006](006-optional-luna-cloud-translation.md). Apple Speech and Apple Translation remain
the default local path. The network entitlement does not authorize background upload,
telemetry, media transfer, or any host other than the explicitly documented provider endpoint.

## Consequences

- A media-framework compromise has a smaller filesystem blast radius.
- Security-scoped bookmark lifecycle and save-panel flows are mandatory product behavior.
- Distribution automation is part of the release gate, not a later packaging concern.
- Future helpers, FFmpeg, or binary model runtimes require their own sandbox and provenance
  review rather than inheriting trust from the app.
