# LocalSub

LocalSub is a privacy-first macOS desktop application that turns Japanese or English
speech in a video into editable Japanese captions and exports a new captioned video.

The product is intentionally local-first. Its first supported product slice targets
Apple Silicon Macs running macOS 26 or later and accepts SDR MP4/MOV files that
AVFoundation can decode.

## Repository layout

- `Sources/LocalSubCore`: deterministic domain logic and provider contracts
- `Sources/LocalSubApple`: Apple Speech, Translation, and AVFoundation adapters
- `Sources/LocalSubCloud`: optional bounded GPT-5.6 Luna text translation adapter
- `Sources/LocalSubCLI`: developer and dogfooding CLI
- `Sources/LocalSubApp`: SwiftUI desktop application
- `Tests`: TDD unit and integration tests
- `docs/architecture`: design and architecture decisions
- `docs/security`: repository threat model
- `docs/qa`: dogfooding inventory and manual verification assets

See [software-design.md](docs/architecture/software-design.md) for the authoritative
design.

## Build and test

LocalSub requires Apple Silicon, macOS 26, and Xcode 26 or later.

```bash
swift test --scratch-path /tmp/localsub-tests
./scripts/build-app.sh
open .build/app/LocalSub.app
```

The build script produces an ad-hoc signed, sandboxed local dogfood app. A distributable
build additionally requires Developer ID signing, Hardened Runtime, notarization, and
stapling; ad-hoc builds are intentionally rejected by Gatekeeper assessment. Release owners
use `scripts/build-release.sh`, which fails closed unless the signing identity and notarytool
keychain profile are provided, and ends with `stapler validate` plus `spctl --assess`.

## Developer CLI

```bash
swift run --scratch-path /tmp/localsub-cli localsub input.mp4 \
  --output captioned.mp4 --language japanese
```

Use `--language english` for English speech. Apple Translation is the default and only uses
already installed models. `--translation luna` explicitly selects GPT-5.6 Luna and requires an
`OPENAI_API_KEY` injected into that process; `--glossary terms.txt` accepts up to 32 KiB of
`source=日本語` entries. Luna CLI runs also require `--acknowledge-luna-data-transfer` after reading
the disclosure printed by the command. Never commit the key. Progress is emitted as one JSON object
per line on standard error.

The Desktop app can store its OpenAI key in the local, non-synchronizing macOS Keychain. Luna
mode asks for confirmation on every generation and sends only the on-device English transcript
units and glossary—not video, audio, paths, or filenames. Requests set `store: false` to avoid
default Response-object storage. Unless the API organization/project has applicable data controls,
OpenAI documents separate abuse-monitoring retention of up to 30 days and encrypted prompt caching
of up to 24 hours. Apple Translation remains available for an entirely local translation path.

The desktop app supports editable two-line cues, burned-in MP4 output, and a separate UTF-8
SRT save action. MP4 export asks for a destination folder so the sandbox can safely stage and
atomically publish the fixed output filename. Existing output files are not silently replaced.
