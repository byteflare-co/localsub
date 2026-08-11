# Security policy and invariants

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
  updated threat model, bounded egress contract, and user-visible consent. The sole current
  exception is the optional text-only Luna path specified by ADR-006.

Critical/high examples include exploitable unsafe media processing, arbitrary path overwrite,
or silent off-device disclosure. Correctly rejected malformed input and local denial of service
within documented resource bounds are robustness concerns rather than vulnerabilities.
