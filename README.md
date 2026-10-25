# Nerd Fonter

A minimal macOS app to browse, preview, install, update, and remove [Nerd Fonts](https://www.nerdfonts.com).

- Live previews of any family before installing — only the faces needed are downloaded.
- One-click install of all variants (standard, Mono, Propo) into `~/Library/Fonts`.
- Detects Nerd Fonts installed by other means (Homebrew, by hand) and offers updates.
- Uninstall moves files to the Trash. Favorites. No dependencies, no background work.

Requires macOS 26.

## Build

```sh
make run    # build build/NerdFonter.app and open it
make test   # run tests
```

`swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

## Shortcuts

| | |
|---|---|
| ⌘↩ | Install or update the selected font |
| ⌘D | Add to / remove from Favorites |
| ⌘1 – ⌘4 | Show All, Installed, Favorites, Updates |
| ⌘F | Search |
