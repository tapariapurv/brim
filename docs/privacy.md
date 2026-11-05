# Privacy

Brim reads nothing that belongs to other tools: no other app's Keychain items, auth files, logs,
databases, or environment variables. It holds only the credentials you add in the app, and it calls
only the provider APIs those accounts need.

## Credentials stored on this Mac

- OAuth tokens and API keys live in the app's own Keychain service
  (`com.robinebers.openusage.accounts`), one item per account. Removing an account deletes its item.
- A [CLIProxyAPI hub](cliproxyapi.md)'s management key lives in `com.robinebers.openusage.cliproxy-hubs`
  and is deleted with the hub. Hub accounts hold no token.
- Account names, the layout, settings, and the last fetched usage live in the app's preferences.
- Provider responses are never written to disk. Nothing syncs to iCloud.
- The [`brim` command](cli.md) reads only that last fetched usage. It makes no network request
  and reads no Keychain item.
- A [proxy](proxy.md) password stays in your `~/.brim/config.json`. Brim reads it but never
  writes or logs it.

## Screen sharing

**Settings → Privacy → Hide From Screen Share** shows the app icon in the menu bar instead of your
usage while your screen is shared or recorded. It is off by default and doesn't hide the panel.

## Telemetry

Brim collects none.
