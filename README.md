# DriveScanner

macOS (SwiftUI) helper to discover user-created content at the top level of your home directory (outside usual Apple locations), see total sizes of **Pictures**, **Music**, and **Movies**, select what to keep, export an **HTML** inventory, and **copy** or **zip** selections for migration.

## Requirements

- macOS **15** (Sequoia) or later  
- Swift **6** (Xcode 16+ or matching toolchain)

## Build and run

```bash
cd /path/to/DriveScanner
swift build
swift run DriveScanner
```

Run tests:

```bash
swift test
```

Open in Xcode: open `Package.swift` as a Swift package.

## Privacy and permissions

- **Local only**: scanning and export use `FileManager` and (for zip) `/usr/bin/ditto` on paths you choose. No network or analytics are built in.
- **User data**: the app reads directory listings and file metadata under your home folder when you tap **Scan my home folder** and when you export. It does not upload data.
- **Full Disk Access**: v1 does not scan `~/Library` as a candidate. If you later extend scanning into protected locations, users may need **System Settings → Privacy & Security → Full Disk Access** for the app (or Terminal when using `swift run`).

## Distribution

For use outside your own machine, sign and notarize the built app per Apple’s guidelines.
