# xcross icon compiler prototype

A one-time, standalone proof of Linux iOS app icon compilation. It uses xtool-org/AssetKit at pinned revision e763558b55fcbb5a443b1d7b2c6f0972d8bd14f7.

Requirements: Swift 6.3+ (with SwiftPM), git, network for the first dependency resolution.

Usage:

    ./compile.sh "$WORDUP_ROOT" wordup_full

Expected output under `$WORDUP_ROOT/build/xcross-icon-preview/wordup_full/`:

- `Assets.car`
- `IconPlistAdditions.plist` with `CFBundleIconName`, `CFBundleIcons`, `CFBundleIcons~ipad`, and fallback icon entries
- loose PNG files for SpringBoard fallback

This deliberately does not alter the WordUp project, modify Info.plist in a built app, sign, or install. AssetKit rejects catalogs with multiple `.appiconset`s; this tool stages only the chosen flavor in a temporary catalog.

After validating compilation, integrate output into the xcross bundle assembly phase and test on the iPhone, preserving other selected resources.

Fedora/SELinux: v2 stages icon files as bytes rather than using Foundation.copyItem to avoid preserving restricted Linux metadata.
