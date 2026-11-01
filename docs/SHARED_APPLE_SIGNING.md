# Shared Apple Distribution signing (Wavo / TideCam / CipherVault)

## Status

This repository has an **opt-in, read-only Fastlane Match signing path**.
The shared signing store has **not** yet been initialized. These workflows do
not assume possession of an Apple Distribution certificate's private key.

**Never revoke an existing certificate solely because a CI runner has no
signing identity.** Apple's portal holds the public certificate, not its
exportable private key. Distribution certificates can sign several apps
from the same developer team, while App Store provisioning profiles are
app-ID specific.

The read-only Apple audit on 2026-11-01 observed:
- `AJZTAG7VP4`: Wavo and Wavo Live Activity profiles
- `RL2774MQCA`: Snapshift profile
- `XMAUN696W6`: TideCam profile

All three had active linked profiles. No one has authorized automatic
revocation, and none is required to **reuse** a certificate that has an
available corresponding private key.

## One-time setup still required

1. **Locate an existing, exportable signing identity.** On the trusted Mac
   that generated one of the three distribution certificates, open
   **Keychain Access > My Certificates**. Verify that the matching
   **Apple Distribution** certificate expands to show a **private key**.
   Export the certificate and private key as a password-protected `.p12`.
   The Apple App Store Connect `.p8` API key is **not** this private key.
   If none of the existing keys is accessible, stop: a revocation/new
   certificate or an alternate signing service is required. Do not guess.

2. **Create a new PRIVATE GitHub repository** dedicated to encrypted Match
   storage, for example `jdarkyeka6/ios-signing`. Do **not** create a public
   certificate repository or upload an unencrypted `.p12`.

3. On the trusted Mac, set up Fastlane Match for the Apple team and that
   private signing repo. Use `fastlane match import` to import the matching
   certificate (`.cer`), private key (`.p12`) and relevant existing
   profiles. Use a strong unique `MATCH_PASSWORD`. Confirm the stored
   cert's identifier matches the active Apple distribution cert selected.

4. Once a certificate is imported, create/import app-specific App Store
   profiles in the shared store for the following bundle IDs:
   - `lol.wavo.app`
   - `lol.wavo.app.WavoLiveActivity`
   - `com.jdarkyeka6.TideCam`
   - `com.jdarkyeka6.calculator`

   Profiles can be issued for these apps using the **same** distribution
   certificate. Review any Match prompts carefully: do not permit it to
   create or revoke a distribution certificate during bootstrap.

5. Give each app repository read-only access to the private signing repo
   using limited-scope GitHub credentials. Add these four GitHub Actions
   secrets in **each** app repository:

   | Secret | What it contains |
   | --- | --- |
   | `MATCH_GIT_URL` | HTTPS clone URL of private signing repository |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 of `username:GitHub-token` (token read-only for signing repo) |
   | `MATCH_PASSWORD` | Unique Fastlane Match encryption passphrase |
   | `APPLE_TEAM_ID` | Existing Apple developer team ID |

   Each app's existing App Store Connect API secrets remain required:
   `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` (CipherVault)
   or `ASC_KEY_CONTENT` (Wavo/TideCam).

   **Never paste these values into chat or commit them to GitHub.**
   Use GitHub Settings > Secrets and variables > Actions.

6. First verify the Match contents on a trusted machine; then run the
   opt-in shared TestFlight workflow. **Do not switch any existing
   automatic release workflow until the new signing flow has succeeded.**

## How CI now behaves

- Match is invoked with `readonly: true`, so CI downloads only existing
  identities and profiles. It cannot allocate a new distribution cert.
- Signing identities remain encrypted at rest in the PRIVATE Match store.
- The CI job retrieves and installs the identity into an ephemeral keychain.
- Every app maintains its own bundle ID and provisioning profile.
- Existing certificates are **not** automatically revoked.
- Main production/release paths stay unchanged until the migration is
  fully validated and merged explicitly.

## Repository migration links

- CipherVault: `jdarkyeka6/calculator-`, branch `feature/ciphervault-ios-v1`
- Wavo: `jdarkyeka6/wavo-cleaned`, branch `ci/shared-signing-preview`
- TideCam: `jdarkyeka6/tidecam`, branch `ci/shared-signing-preview`

## Recovery and rotation

Protect a backup of the encrypted Match repository and its passphrase.
If private signing keys are lost, Apple's certificate listing alone cannot
recreate them. Rotate before expiry, coordinate app profiles, and validate
each signed build before moving release workflows.

## References

- https://docs.fastlane.tools/actions/match/
- https://developer.apple.com/help/account/certificates/create-distribution-certificates/
