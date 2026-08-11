# Distribution

LocalSub's source code is open source under Apache-2.0. Distributing an official macOS binary is a
separate release and trust process.

The desktop app and CLI use separate packaging workflows. See [CLI distribution](cli-distribution.md)
for the versioned GitHub Release, Homebrew Cask, and verified curl installer.

## Current state

`scripts/build-app.sh` creates an ad-hoc signed app for local development. It is intentionally not
an end-user release. `scripts/build-release.sh` defines the direct-distribution security gates but
requires Apple-issued credentials that must never be committed.

## Direct distribution outside the Mac App Store

An official download sold or distributed by 株式会社Byteflare requires:

1. An organization membership in the Apple Developer Program.
2. A `Developer ID Application` certificate controlled by the release owner.
3. Hardened Runtime and the minimum sandbox entitlements already declared by LocalSub.
4. A timestamped signature over the final app bundle.
5. Submission to Apple's notary service using `notarytool`.
6. Stapling and validation of the notarization ticket.
7. A final Gatekeeper assessment with `spctl --assess`.
8. A versioned, checksummed download and an authenticated update strategy before automatic updates.

The current release script implements steps 2–7 and fails closed when its signing identity or
notary profile is absent. Direct distribution is managed by the developer; payment, downloads,
updates, refunds, and customer support are not provided by Apple.

## Mac App Store

Mac App Store distribution uses the Apple Developer Program plus App Store Connect, store signing,
metadata, App Review, and Apple's commerce agreements. App Sandbox is required. LocalSub is already
sandbox-oriented, but a store release still needs a dedicated Xcode archive/submission workflow and
review of every entitlement and network disclosure.

## Organization enrollment

Apple currently requires organizations to provide their legal entity name, D-U-N-S Number, legal
authority to bind the company, a work email on the organization's domain, and a public website. The
seller name should therefore be registered as `株式会社Byteflare`, not an individual's name.

The Apple Developer Program is currently 99 USD per membership year, or the local-currency price
shown during enrollment. The Enterprise Program is for eligible internal employee distribution,
not general customer sales.

## Credential handling

Use the user-global `op-cached` workflow to inject signing and notarization credentials. Never add
certificates, private keys, Apple credentials, notary profiles, or plaintext environment files to
the repository.

## Apple references

- [Choosing a membership](https://developer.apple.com/support/compare-memberships/)
- [Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- [Developer ID](https://developer.apple.com/support/developer-id/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
