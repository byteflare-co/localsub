# Security policy and invariants

## Supported versions

LocalSub has not published a stable binary release yet. Security fixes currently target the latest
commit on `main`. Once versioned releases begin, this section will list supported release lines.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/byteflare-co/localsub/security/advisories/new).
Do not open a public issue, pull request, or discussion containing exploit details.

Include the affected commit or version, impact, reproduction conditions, and the smallest safe
proof of concept. Do not submit private media, real transcripts, API keys, signing certificates,
notarization credentials, or unrelated personal data. Maintainers will acknowledge a complete
report as soon as practical, coordinate remediation and disclosure with the reporter, and credit
the reporter unless anonymity is requested.

This process is for vulnerabilities in LocalSub. Translation quality problems and correctly
rejected malformed input belong in normal bug reports unless they cross a security boundary.

## Security design

LocalSub processes untrusted local media and potentially sensitive speech. Security issues
include arbitrary code execution through media parsing, unintended disclosure of transcript
content, path traversal or overwrite, unbounded resource consumption, unsafe subprocess use,
and project-file corruption.

Repository-wide invariants:

- Treat media, project JSON, provider output, filenames, and subtitle text as untrusted.
- Never construct shell commands. Future subprocesses use executable URLs and argument arrays.
- Never overwrite source media. Publish exports through a validated unique temporary file.
- Bound file size, duration, dimensions, spans, cues, and text length before expensive work.
- Keep transcript and translation text out of routine logs and telemetry.
- Validate all decoded project data before it reaches rendering or UI state.
- Preserve cancellation and stale-job isolation across every asynchronous boundary.
- Do not add network providers, analytics, or diagnostic upload without an explicit ADR,
  updated threat model, bounded egress contract, and user-visible consent. Content egress is
  limited to the optional text-only Luna path specified by ADR-006. ADR-007 separately permits
  an explicit opt-in, metadata-only GitHub release check with no media-derived content.
- Publish CLI source archives only from a clean, version-tagged commit. Do not attach CLI
  executables, bottles, or Casks. Pin the custom source archive SHA-256 directly in the Formula
  and installer, require immutable release assets, and fail closed before publishing a local build.
- Treat release archives, checksum manifests, Homebrew definitions, and installer download paths
  as untrusted until their structure, size, version, and authenticity checks succeed.

Critical/high examples include exploitable unsafe media processing, arbitrary path overwrite,
or silent off-device disclosure. Correctly rejected malformed input and local denial of service
within documented resource bounds are robustness concerns rather than vulnerabilities.
