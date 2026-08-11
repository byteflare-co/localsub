# ADR-002: Replaceable intelligence and media providers

Status: accepted

## Decision

Transcription, translation, media inspection, and rendering are protocol boundaries.
Apple implementations are candidates, not domain dependencies. Apple Speech and
ArgmaxOSS/WhisperKit must be compared on a fixed corpus before choosing the default ASR.

## Consequences

- Tests use deterministic fakes.
- Provider changes do not migrate project semantics.
- Provider identity and environment are recorded for auditability.
- The first implementation may ship with one provider while retaining the boundary.
