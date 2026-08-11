# Contributing to LocalSub

Thank you for helping improve LocalSub. Please keep changes focused, reviewable, and safe for
people processing private video and speech.

## Before you start

- Use GitHub Issues for confirmed bugs and scoped feature proposals.
- Do not open a public issue for a security vulnerability. Follow [SECURITY.md](SECURITY.md).
- For substantial architecture or provider changes, open an issue before implementation.
- Never commit recordings, transcripts, API keys, signing certificates, notarization credentials,
  or machine-specific evidence paths.

## Development environment

LocalSub currently requires an Apple Silicon Mac, macOS 26 or later, and Xcode 26 or later.

```bash
git clone https://github.com/byteflare-co/localsub.git
cd localsub
swift test --scratch-path /tmp/localsub-tests
./scripts/build-app.sh
open .build/app/LocalSub.app
```

The local app build is ad-hoc signed for development. It is not a distributable release.

## Pull requests

1. Create a topic branch from `main`.
2. Add or update tests before changing behavior.
3. Keep transcript text, filenames, and other user data out of logs and fixtures.
4. Run the complete Swift test suite and `./scripts/build-app.sh release`.
5. Explain the user-visible change, security/privacy impact, verification evidence, and anything
   intentionally left out.

Pull requests should be small enough to review independently. Maintainers may request an ADR for
changes to persistence, provider boundaries, networking, sandbox permissions, or distribution.

## Licensing contributions

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
LocalSub is provided under the [Apache License 2.0](LICENSE), as described by section 5 of that
license. Mark material that is not intended as a contribution clearly and in writing.
