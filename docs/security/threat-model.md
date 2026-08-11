# Repository threat model

## Overview

LocalSub is a local-first, single-user macOS application and CLI that reads untrusted video and
project files, invokes on-device speech and optional cloud text translation providers, renders user-editable
captions, and writes new media. Sensitive assets are source media, speech content,
translations, filenames, output integrity, file-system authority granted through file panels,
and application availability.

## Threat Model, Trust Boundaries, and Assumptions

Trust boundaries exist between the user-selected filesystem and the app, AVFoundation media
parsers and application code, Apple-managed model assets and provider adapters, untrusted
provider text and validated domain models, the background job actor and MainActor UI, and
private temporary output and user-visible publication.

An attacker may control a selected media file, imported project JSON, embedded metadata,
codec payloads, filenames, transcript-like text, and a destination that changes between
selection and publication. The operator controls explicit file selection, edit acceptance,
and export destination. Developers control dependency versions, entitlements, bundled assets,
and release signing.

The host OS, Apple frameworks, code signature, and user account are assumed uncompromised.
A malicious process already running with the same macOS user identity is not a separate security
principal: it can replace the final output after publication and remains out of scope. Publication
still detects symlink and ordinary replacement changes, and cleanup refuses to remove a staging
file whose captured device/inode identity changed. Compromise of the whole user session and
physical attackers remain out of scope.
LocalSub exposes no server or application account surface. OpenAI account/project security and
provider-side multi-tenancy are external dependencies; LocalSub limits the credential and data
it transmits but cannot enforce provider retention or availability.

Security invariants are defined in `SECURITY.md`. The application must fail closed when runtime
capability, model availability, media support, resource policy, or output validation is unknown.

## Attack Surface, Mitigations, and Attacker Stories

### Media ingestion

A crafted codec stream may exploit framework decoders or cause excessive CPU, memory, disk, or
duration. v1 restricts containers/codecs, validates asynchronously before work, streams audio,
centralizes resource limits, relies on OS-patched AVFoundation rather than bundled parsers, and
runs the signed app under App Sandbox and Hardened Runtime with user-selected file authority.

### Project import and caption text

Malformed JSON could produce invalid time ranges, huge allocations, control characters, or
rendering failures. Versioned decoding has byte/count limits and complete domain validation.
Caption text is data; it never becomes a format string, path, HTML, or shell syntax.

### File access and publication

A confusing path, symlink, existing file, or race could overwrite source or unrelated content.
The app obtains explicit user destinations, compares canonical resource identifiers, renders to
a private random temporary directory, stages on the destination volume, validates output, and
uses coordinated publication. It rechecks symlink/regular-file/resource identity and job lease
immediately before publication; cross-volume movement is not assumed atomic. These checks protect
against accidental and non-concurrent path replacement. They do not claim isolation from a
malicious same-user process racing between adjacent filesystem syscalls; macOS provides no such
trust boundary for a user-selected directory.

### Concurrency and cancellation

Late callbacks could attach results from an old video to a new project or publish after cancel.
A coordinator actor owns one generation-tagged job; every result and publication checks the
active generation and cancellation state.

### Privacy and model assets

Routine logs could leak filenames or speech. Logs are metadata-only and diagnostics are explicit.
Speech recognition and media processing stay on device. Apple-managed model downloads may use
the network. Apple Translation is the default local translation path. When the user explicitly
selects and confirms Luna, English transcript units and glossary entries cross the network boundary
to the fixed Responses API endpoint. Video, audio, paths, and filenames do not. The credential is
stored in non-synchronizing Keychain storage or injected into a development/CLI process, never
logged. Input/batch/time and streaming response bounds limit cost and memory abuse; structured
output and ID correlation treat provider text as untrusted. `store: false` avoids default Response
object storage but does not eliminate OpenAI's documented abuse-monitoring retention (up to 30
days) or encrypted prompt caching (up to 24 hours without ZDR), so the UI and ADR disclose those
organization/project-dependent limitations.

Prompt injection in spoken content or glossary text could ask the model to ignore translation
rules. Both fields are encoded as untrusted JSON data, instructions prohibit following their
commands, no tools are enabled, and output remains limited to validated Japanese strings. This
reduces impact but does not make translation semantically infallible; the review UI remains a
required human checkpoint.

### Future FFmpeg or model dependencies

Bundled native binaries and model loaders enlarge the supply-chain and parser attack surface.
They require pinned provenance, license notices, signature verification where available,
argument-array invocation, sandbox-compatible execution, and a revised threat model.

## Severity Calibration (Critical, High, Medium, Low)

- **Critical:** reliable arbitrary code execution from opening supported media; silent upload of
  source media/transcripts; arbitrary write outside user-authorized scope with system impact.
- **High:** overwrite or destruction of arbitrary user files; cross-job confusion that publishes
  sensitive captions into another selected video; persistent secret transcript leakage in logs.
- **Medium:** bounded but repeatable application denial of service bypassing declared limits;
  malformed projects causing persistent corruption; export produced at the wrong path but without
  overwriting existing data.
- **Low:** non-sensitive metadata disclosure, recoverable single-job failure, or cosmetic caption
  corruption that is visible before export.

Repository: new-chat
Version: design-v1
