# ADR-007: Bounded CLI update notices

Status: accepted

## Context

Users need to learn that a newer LocalSub CLI is available without changing the semantics of
their command, silently installing code, or sending media-derived content off device. GitHub's
`releases/latest` endpoint excludes prereleases, so the current alpha channel must inspect the
bounded public releases list instead.

## Decision

The CLI keeps update checks disabled until the user explicitly opts in with
`localsub update-check enable --acknowledge-metadata`. Once enabled, normal commands perform an advisory update check at
startup at most once every 24 hours. Help, version, and preference commands never access the
network. A check sends one
`GET` request to:

```text
https://api.github.com/repos/byteflare-co/localsub/releases?per_page=20
```

The request contains only ordinary HTTPS metadata plus a `LocalSub/<version>` User-Agent. Redirects
are rejected so the client cannot be sent to an undeclared host. It does
not contain media, audio, transcript or translation text, glossary content, paths, filenames,
API keys, or persistent user identifiers. The request has a two-second request/resource timeout.
Responses whose declared size exceeds 256 KiB are rejected before body processing, and streaming
stops as soon as actual data would exceed 256 KiB. Only non-draft semantic-version tags with an exact
`https://github.com/byteflare-co/localsub/releases/tag/<tag>` URL are eligible.

The result is cached under the user's macOS cache directory. A nonblocking cross-process file lock
prevents concurrent invocations from issuing duplicate requests. A successful or failed attempt is
throttled for 24 hours so an offline machine is not delayed on every invocation. Cache read/write
failure and all network or schema errors are silent and cannot fail the requested CLI command.

If a newer version exists, LocalSub writes a Japanese notice to standard error. Generate commands
emit that notice as one JSON object so the documented NDJSON progress stream remains valid. It
never downloads or installs an update. Standard output remains machine-readable. Users can revoke
consent with `localsub update-check disable`, or temporarily suppress an enabled check with
`LOCALSUB_NO_UPDATE_CHECK=1`; this is disclosed by the installer, Homebrew caveat, README, and
`--help`.

## Security consequences

GitHub and the network operator can observe normal connection metadata such as source IP, time,
TLS destination, and the LocalSub version in User-Agent. This opt-in metadata egress is distinct
from the separately consented Luna content path.
Release metadata remains untrusted: version ordering, size, draft state, host, and path are
validated before display. The source archive checksum, exact release commit, verified Formula,
and immutable release assets remain the authority for installation; the update notice alone
confers no trust.
