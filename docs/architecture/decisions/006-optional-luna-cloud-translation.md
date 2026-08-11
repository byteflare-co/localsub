# ADR-006: Optional GPT-5.6 Luna subtitle translation

Status: accepted for dogfood; live success remains gated by API project model access

## Decision

English speech is always transcribed on-device with Apple Speech. Users may then choose either
Apple Translation, which remains the default and stays local, or exact model ID
`gpt-5.6-luna` through `POST https://api.openai.com/v1/responses`.

The Luna path is opt-in twice: the user selects it and confirms a per-generation disclosure.
The disclosure appears before transcription begins. Only the resulting English translation
units and the user-entered glossary are sent. Video bytes, audio bytes, local paths, filenames,
bookmarks, and Apple Speech alternatives are not included. The request uses strict Structured
Outputs, `store: false`, no tools, a fixed HTTPS endpoint, bounded batches and total input, a
five-minute job deadline, and streaming response-size enforcement. Failure is explicit and
never silently falls back to Apple.

The Desktop key is stored as a non-synchronizing generic password in the user's macOS Keychain,
accessible after first unlock on this device. The UI never reads an existing value back into a
text field. `OPENAI_API_KEY` is a development/CLI injection fallback and must not be persisted in
the repository or logs. The app has `com.apple.security.network.client`; App Sandbox cannot
restrict that entitlement to a hostname, so application code pins the only endpoint.

`store: false` avoids the Responses API's default 30-day Response-object application state, but
it is not a promise of zero retention. OpenAI documents two separate default paths: abuse-monitoring
logs may contain prompts and responses for up to 30 days, and—when Zero Data Retention is not
enabled—encrypted prompt-cache key/value tensors may remain on GPU-local storage for up to 24
hours. Approved Zero Data Retention or Modified Abuse Monitoring settings change parts of this
behavior at the organization/project level. These limits are stated in product and test privacy
text rather than being hidden behind “local-first”.

## Required verification

- Before consent: zero OpenAI request.
- After consent: TLS destination is `api.openai.com`; payload contains only translation units,
  glossary, schema, and generation settings.
- Cancel or stale job: no later batch starts and no partial translation reaches UI state.
- Missing key, denied model, network error, oversized input/response, invalid JSON/schema, and
  missing/duplicate IDs fail closed without output publication.
- Release review inspects resolved entitlements and records the test API project/model access.

## Consequences

- Luna can improve naturalness and terminology, but adds cost, latency, remote processing, API
  availability, and retention-policy dependencies.
- Knowledge cutoff is not treated as a live terminology source. The user glossary is the
  deterministic mechanism for new terms; no web-search tool is enabled.
- Privacy-sensitive use should retain Apple Translation or use an API project with appropriate
  data controls.

References: [GPT-5.6 Luna model](https://developers.openai.com/api/docs/models/gpt-5.6-luna),
[OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data).
