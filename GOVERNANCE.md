# Project governance

LocalSub is an open-source project stewarded by 株式会社Byteflare.

## Decision making

Maintainers review issues and pull requests in public whenever security or privacy does not require
confidential handling. Technical decisions prioritize user privacy, safe processing of untrusted
media, accessibility, maintainability, and compatibility with the supported Apple platforms.

Maintainers have final responsibility for roadmap, architecture, releases, security response, and
whether a contribution is merged. Substantial or irreversible changes should be proposed in an
issue and documented with an architecture decision record before implementation.

## Maintainers

Repository ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS). Maintainers are
expected to disclose relevant conflicts of interest and to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Releases and security

Only 株式会社Byteflare may designate a build as an official LocalSub release. Official release
artifacts must pass the documented signing, notarization, and verification gates. Vulnerabilities
must be reported through the private process in [SECURITY.md](SECURITY.md).

## Changes to governance

Governance changes are made through reviewed pull requests. This document does not override the
[Apache License 2.0](LICENSE), which governs use, modification, and redistribution of the software.
