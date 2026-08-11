# ADR-003: Versioned project JSON is the source of truth

Status: accepted

## Decision

Persist source spans, translations, display cues, and render settings as distinct,
versioned records using rational time. SRT, preview layers, and rendered video are derived.

## Consequences

- Translation and layout can be retried without ASR.
- Hand edits have provenance and survive re-rendering.
- Schema migration and validation are release responsibilities.
- Generated video alone cannot restore all editable state.
