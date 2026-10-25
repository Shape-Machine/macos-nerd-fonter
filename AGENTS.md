# AGENTS.md

## Project

**Nerd Fonter** — a minimal macOS app to browse, preview, install, and manage [Nerd Fonts](https://www.nerdfonts.com) on the user's system.

- Repo: https://github.com/Shape-Machine/macos-nerd-fonter (`git@github.com:Shape-Machine/macos-nerd-fonter.git`)

## Workflow

- **Always work in a feature branch.** Never commit directly to `main`.
- Branch names: `feat/…`, `fix/…`, `chore/…`, `docs/…` — short and descriptive.
- Merge only through GitHub pull requests into `main`. One focused change per PR.
- After a PR is merged: confirm it's merged, switch to `main`, `git pull --ff-only`, `git fetch --prune`, and delete the merged local branch before starting the next one.

## Principles

1. **Extremely minimal.** Every feature, view, dependency, and line of code must earn its place. When in doubt, leave it out.
2. **Delightful UX.** Fast, obvious, and polished. Native look and feel, thoughtful empty/loading/error states, no friction.
3. **Extremely resource efficient.** Small binary, low memory, near-zero idle CPU, no background work unless the user asked for it. Fetch and render lazily; cache sensibly.

## Decisions

- **Stack:** Swift + SwiftUI only. Zero third-party dependencies (Apple frameworks and system tools only).
- **Target:** macOS 26 Tahoe minimum. Embrace the current design language.
- **Shape:** Single-window Dock app — font list + preview pane.
- **Build:** Swift Package (no `.xcodeproj`). `swift build` plus a small script that wraps the binary into a `.app`.
- **Distribution:** Personal use only for now — no signing, notarization, or release pipeline.

## Commands

- `make run` — build `build/NerdFonter.app` and open it
- `make test` — run tests
- `make clean` — remove build output
- `swift scripts/make-icon.swift` — regenerate `Resources/AppIcon.icns`

## Layout

- `Sources/NerdFonter` — app entry point and SwiftUI views (keep thin)
- `Sources/NerdFonterKit` — models and core logic
- `Tests/NerdFonterKitTests` — Swift Testing tests for `NerdFonterKit`

## Features (v1)

- **Browse** the Nerd Fonts catalog.
- **Preview live, on demand:** selecting a font downloads just that family to a cache and renders it. Default preview is an editable code snippet plus a row of popular glyphs (git, folders, powerline).
- **Install** all variants (standard, Mono, Propo) of a family into `~/Library/Fonts` (current user, no admin).
- **Uninstall** by moving files to the Trash (never hard-delete).
- **Detect** Nerd Fonts already installed by other means (Homebrew, manual).
- **Update** installed families when a newer Nerd Fonts release exists.
- **Favorites** to star fonts.

## Testing

- Swift Testing for core logic (catalog parsing, install/uninstall, detection, updates).
- UI behaviour is tested through `@Observable` view models; no XCUITest. Keep views thin so logic stays testable.
