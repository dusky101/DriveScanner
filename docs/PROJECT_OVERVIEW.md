# DriveScanner — Project Overview

The full end-to-end reference for DriveScanner. `CLAUDE.md` summarises the must-know rules and points here for depth. This file is **not** auto-loaded — read it when you need to get oriented.

## What it is, and for whom

DriveScanner is a macOS desktop app that helps a developer **migrate to a new Mac**. It looks at the top level of your home directory, works out what is genuinely *yours* (versus Apple's standard folders and regenerable junk), shows you how much space each thing takes, and lets you assemble exactly what you want to carry over into a self-contained, optionally-encrypted **migration bundle** that restores onto the new machine with a single script.

- **Platform:** macOS 15 (Sequoia) or later.
- **Toolchain:** Swift 6 (Xcode 16+ / matching toolchain).
- **Packaging:** Swift Package Manager. No third-party dependencies.
- **Privacy posture:** entirely local. No network, uploads, or analytics. Reads the home folder; copies only what you select.

## How to build, run and test

```bash
swift build              # build all targets
swift run DriveScanner   # launch the app (note: it scans the REAL home folder)
swift test               # run the Swift Testing suite
```

Open in Xcode by opening `Package.swift` as a Swift package. The signed/notarised, icon'd app is produced from the **gitignored** `App/DriveScanner.xcodeproj` (scheme `DriveScanner`); `swift build` remains the canonical, source-controlled build. See `.claude/rules/build-and-test.md` for the log-file workflow used to read verbose output.

## Repository layout

```
Package.swift                     SPM manifest — 3 products, macOS 15 platform
README.md                         short user-facing readme (tracked)
Sources/
  DriveScannerCore/               pure models + services (no SwiftUI)
  DriveScannerUI/                 SwiftUI views + design system
  DriveScannerApp/                @main executable (swift run DriveScanner)
Tests/DriveScannerTests/          Swift Testing suite (targets Core)
App/                              Xcode app wrapper (signed/notarised build)
  DriveScanner.xcodeproj          gitignored
  DriveScanner/DriveScannerApp.swift     mirrors the SPM @main entry
  DriveScanner/DriveScanner.entitlements app-sandbox = false (deliberate)
  DriveScanner/Assets.xcassets, DriveScannerIcon.icon   tracked app icon assets
docs/PROJECT_OVERVIEW.md          this file
```

## Architecture & layering

Three SPM targets in a strict dependency line — **Core → UI → App**:

- **`DriveScannerCore`** — the engine. Pure value types and stateless `public enum` service namespaces, all `Sendable`, no SwiftUI/AppKit. `FileManager` is injected (`fileManager: FileManager = .default`) so everything is testable against a temp directory.
- **`DriveScannerUI`** — SwiftUI. `ContentView` owns all state and orchestrates Core; section views are presentation-only; `DesignSystem.swift` holds reusable styling primitives and the cross-module `Notification.Name`s.
- **`DriveScannerApp`** — the `@main` `App` scene; sets the window size and the View/History menu commands.

### Core modules

| File | Responsibility |
|---|---|
| `Models.swift` | Shared vocabulary: `CandidateItem`, `CandidateCategory`, `CodeStack`, `TopLevelFolder`, `ScanResult`, `DirectoryMeasurement`, `MediaFolderMeasurement`, `FolderRollup*`, `HomebrewInfo`, `UserContext`. |
| `HomeScanner.swift` | Enumerates `~`: skips standard Apple folders + junk, applies dotfile allow/block lists, expands parents with ≥3 project children, detects code stacks, and measures sizes (shallow first, then accurate recursive). **Read-only.** |
| `HomebrewService.swift` | Detects `brew` at the two standard prefixes and runs `brew bundle dump --file=-` to capture a `Brewfile`; parses formula/cask/tap/mas counts. |
| `ExportService.swift` | Copies selected items with collision-safe names; zips via `/usr/bin/ditto`. |
| `BundleBuilder.swift` | Assembles a migration bundle: copies payload under `data/` and `dotfiles/`, writes `manifest.tsv`, `restore.sh` (0755), `README.txt`, `inventory.html`, optional `Brewfile`. |
| `ArchiveService.swift` | Wraps `/usr/bin/tar` (`tar.gz`) and `/usr/bin/hdiutil` (AES-256 encrypted DMG, password via stdin). |
| `CopyHistoryStore.swift` | Persists a Codable JSON history of what's been copied; dedupes by path. |
| `HTMLReportBuilder.swift` | Builds the `inventory.html` report (hero, KPI cards, sortable tables, per-folder rollup, media folders, Homebrew). Escapes all user-derived strings. |
| `FileSearchHTMLBuilder.swift` | Builds the standalone `file-search.html` with an embedded file-name index; escapes `</script>` inside the JSON payload. |

### UI structure

`ContentView` composes: `ScanHeader` (scan trigger + progress), `OverviewSection` (media folder sizes + Homebrew tile), a two-panel body — `TopLevelFoldersSection` and `ItemsSection` — `ActionsFooter` (save HTML / create bundle), and a status bar. Sheets: `BundleSheet` (format + destination + DMG password) and `HomebrewDetailSheet`. `DesignSystem.swift` provides `card()`, `SectionHeader`, `PillLabel`, `MetricCard`, `SelectionSummary`, `EmptyStateView`, the category `swatch`/`iconName`, and `PathFormat.tildeHome`.

## End-to-end data flow

1. **Scan** — `ContentView.runScan()` calls `HomeScanner.scan()`, yielding `candidates` (the flat item list) and `topLevelFolders` (folders mapped to their candidate child IDs).
2. **Measure** — each directory is re-measured on a detached task (`HomeScanner.measureDirectory`) and applied back on the main actor (`applyMeasurement`), updating sizes and the file-name index used for search.
3. **Enrich** — media folder sizes (`~/Pictures`, `~/Music`, `~/Movies`) and Homebrew info load asynchronously.
4. **Select** — the user ticks items; running totals (count · bytes) update live. Previously-copied items are shown as already migrated (from `CopyHistoryStore`).
5. **Export** — either:
   - **HTML** — `HTMLReportBuilder` + `FileSearchHTMLBuilder` write `inventory.html` (and a search page) via `NSSavePanel`; or
   - **Bundle** — `BundleBuilder.build()` mirrors the selection into a bundle dir; for `tar.gz`/`encryptedDmg` the bundle is built in a temp dir and `ArchiveService` produces the final archive, then the temp dir is removed.
6. **Record** — successful copies are appended to `CopyHistoryStore` and the rows flip to the "copied" state.

## Migration bundle layout & `restore.sh` contract

```
<bundle>/
  README.txt          human-readable summary
  inventory.html      full readable report
  file-search.html    (optional) in-browser file-name search
  manifest.tsv        # kind \t bundle_path \t restore_path
  restore.sh          bash restorer (0755)
  data/               regular items, mirrored to $HOME/<restore_path>
  dotfiles/           hidden config dirs/files, restored to $HOME/<name>
  Brewfile            (optional) Homebrew packages
```

`restore.sh` reads `manifest.tsv` and, for each entry, copies `data/`/`dotfiles/` content to `$HOME`. It is **idempotent and never overwrites**: existing targets are SKIPPED with a log line. It optionally offers to run `brew bundle` if a `Brewfile` is present. This safety contract must be preserved.

## Persistence

`CopyHistoryStore` serialises `CopiedHistory` (a list of `CopiedEntry { path, sizeBytes, copiedAt, bundleName }`) as JSON with ISO-8601 dates, deduped by path. There is no database; do not introduce SwiftData/Core Data without being asked.

## External processes

Only these, always by absolute path after an `isExecutableFile` check: `/usr/bin/ditto` (zip), `/usr/bin/tar` (tar.gz), `/usr/bin/hdiutil` (encrypted DMG), and the detected `brew` (`bundle dump`). The DMG password is fed to `hdiutil` via stdin (`-stdinpass`) so it never appears in process arguments.

## Security & privacy posture (why it is the way it is)

- **Un-sandboxed** (`app-sandbox = false`) so it can read the whole home folder. `~/Library` is intentionally not scanned as a candidate (per the README); broadening into protected locations would require Full Disk Access.
- The dotfile allow-list includes credential-bearing directories (`.ssh`, `.gnupg`, `.aws`, `.azure`, `.gcloud`, `.kube`, `.gitconfig`). Bundles can therefore contain secrets — the **AES-256 encrypted DMG** is the intended way to move them safely.
- All generated HTML escapes user-derived content (file names, user name, folder labels), including inside embedded `<script>` JSON, to avoid injection when reports are opened in a browser.

## Conventions

British English in UI copy, comments and docs (`Locale(identifier: "en_GB")`). Swift 6 strict concurrency (`@MainActor` for UI, `Task.detached` for heavy IO). `///` doc comments and `// MARK: -` dividers. Tests use Swift Testing (`@Suite`/`@Test`/`#expect`) against temp directories with injected `FileManager` — never the real `~`.

## Getting oriented (new session checklist)

1. Read `CLAUDE.md` (loaded automatically) for the invariants and commands.
2. Skim `Models.swift` for the shared types, then the service you're touching.
3. For UI work, start at `ContentView` to see how state and services connect.
4. `swift build` and `swift test` before and after changes; never run the app or tests against data you cannot afford to read.
