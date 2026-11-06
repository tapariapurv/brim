# Updates

Brim updates itself through Sparkle.

- A release build checks for a new version every hour, downloads it, installs it, and relaunches. If you're using the panel at that moment, it installs when you quit or at a later check.
- A pending update shows as a banner at the top of the dashboard and a dot on the menu bar icon.
- **Options → Check for Updates…** checks right away. It is disabled in dev builds, which have no update feed.

## Releasing

1. Once per Mac, create the signing key with Sparkle's `generate_keys`, found under `.build/artifacts` after a build. It stays in your Keychain.
2. Run `script/make_dmg.sh <version>`. It builds `dist/Brim.dmg`, signs it with that key, and updates `site/appcast.xml`.
3. Upload the DMG to a `v<version>` GitHub release as `Brim-<version>.dmg`.
4. Publish `site/`, which serves the feed.

Back the key up with `generate_keys -x <file>`: without it you can't ship updates to existing installs.
