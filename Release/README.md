# Sparkle packaging (maintainers)

Public helpers so local `scripts/package.sh` (gitignored) can embed Sparkle
without copying unpublished scripts.

## Tom: generate keys once

After this tree is on your machine:

```bash
swift package resolve
# Sparkle CLI lives under .build/artifacts/sparkle/Sparkle/bin/
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Accept the Keychain default. **Never commit the private key.** Backup that
Keychain item yourself.

Copy the printed public key into `Resources/Sparkle.plist` → `SUPublicEDKey`,
replacing `REPLACE_WITH_TOMS_SPARKLE_PUBLIC_KEY`. Commit **only** that public
key. Do not use a key generated on a contributor fork.

## Inject into the generated Info.plist

When building `Burnrate.app` (not Burnrate-dev), merge
`Resources/Sparkle.plist` into `Contents/Info.plist`:

- `SUFeedURL`
- `SUPublicEDKey`
- `SUEnableAutomaticChecks`
- `SUScheduledCheckInterval` (86400)
- `SUVerifyUpdateBeforeExtraction`

Then:

```bash
bash Release/embed-sparkle-framework.sh /path/to/Burnrate.app
```

The `Tokens` binary links `Sparkle.framework`, so copy the framework into
**every** packaged `.app` (including `Burnrate-dev.app`). Do not start Sparkle
in Burnrate-dev — skip injecting `SUFeedURL` / `SUPublicEDKey` there; the
in-app controller also refuses to start for `.dev` builds.

## Sparkle-only releases

Do not attach `.minisig` for new tags. `package.sh --release` should run:

```bash
VERSION=x.y.z bash Release/prepare-sparkle-appcast.sh
```

Upload the zip to the GitHub Release, then commit the updated `appcast.xml`.

Keep `burnrate.key` locally until this tag is out; then optional archive.
Old minisign-only clients cannot jump to this tag — they need the bridge
release that still shipped Sparkle plus a minisign zip.

Upload the zip to the GitHub Release, then commit the updated `appcast.xml`.
