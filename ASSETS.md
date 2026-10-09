# Asset Provenance

This repository contains project-owned Ring Stats artwork and Apple system
symbols rendered by macOS at runtime. It does not include Oura logos, product
artwork, proprietary typefaces, or extracted application assets.

| Asset | Purpose | Provenance |
| --- | --- | --- |
| `Sources/RingStats/Resources/ring-stats-logo.svg` | In-app split-ring mark | Maintainer-designed Ring Stats vector, finalized in the project Figma file |
| `Sources/RingStats/Resources/Assets.xcassets/RingStatsMenuIcon.imageset/` | 17 pt menu-bar template icon | Raster exports of the project split-ring vector at 1× and 2× |
| `native/AppIcon.svg` and `AppIcon.appiconset/` | Finder/Spotlight application icon | Project-owned derivative of the Ring Stats identity |
| `HolographicMarble.jpg` | Bundled Holographic theme | Project-owned procedural marble rendered by `scripts/assets/holographic_marble.swift` (domain-warped noise, seed 21); no third-party imagery |
| `LandscapeBackground.png` | Bundled Landscape theme | Project-owned generated landscape created for Ring Stats; no Oura, person, or product imagery |
| `.github/assets/ring-stats-banner.*` | README identity banner | Maintainer-provided export from the project Figma file |
| `.github/assets/ring-stats-hero.png` | README hero | The Holographic popover rendered by the app at 680 pt and 2x on a transparent background with synthetic gallery values |
| `.github/assets/ring-stats-social-preview.png` | GitHub social preview (1280 by 640) | The same render on the warm canvas with the app name; upload it under Settings, Social preview |
| `.github/assets/ring-stats-themes-v6-light.png`, `-dark.png` | README theme showcase | The Landscape, Holographic, and Ring Stats themes rendered by the app at 680 pt and 2x on a transparent background, stacked under their names; the light and dark files differ only in the name color, for GitHub's light and dark modes |

In the README theme showcase, every value is a synthetic fixture from the state
gallery, chosen to demonstrate layout. None of them should be used as product,
health, or API evidence.

SF Symbols referenced by name in Swift source are supplied and rendered by
macOS. They are not bundled project logos. Apple permits SF Symbols inside
interfaces subject to Apple's license and platform guidance; do not repurpose
them as an application or project identity.

When adding assets, document creator/source, license or ownership, generation
method, material edits, and whether displayed data is synthetic. Never commit
private health screenshots or third-party brand assets without permission.
