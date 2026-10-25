# Nerd Fonter

A minimal macOS app to browse, preview, install, update, and remove [Nerd Fonts](https://www.nerdfonts.com).

- Live previews of any family before installing — only the faces needed are downloaded.
- One-click install of all variants (standard, Mono, Propo) into `~/Library/Fonts`.
- Detects Nerd Fonts installed by other means (Homebrew, by hand) and offers updates.
- Uninstall moves files to the Trash. Favorites. No dependencies, no background work.

Requires macOS 26.

## Install

1. Download `NerdFonter.zip` from the [latest release](https://github.com/Shape-Machine/macos-nerd-fonter/releases/latest) and unzip it.
2. Move **NerdFonter** to Applications.
3. The app isn't signed or notarized, so macOS blocks the first launch. Either open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**, or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/NerdFonter.app
   ```

## Build

```sh
make run    # build build/NerdFonter.app and open it
make test   # run tests
```

`swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

## Release

Push a version tag; GitHub Actions tests, builds a universal app, and publishes it as a release.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Shortcuts

| | |
|---|---|
| ⌘↩ | Install or update the selected font |
| ⌘D | Add to / remove from Favorites |
| ⌘1 – ⌘4 | Show All, Installed, Favorites, Updates |
| ⌘F | Search |
