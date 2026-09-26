# Asset Provenance

This repository contains project-owned Ring Stats artwork and Apple system
symbols rendered by macOS at runtime. It does not include Oura logos, product
artwork, proprietary typefaces, or extracted application assets.

| Asset | Purpose | Provenance |
| --- | --- | --- |
| `Sources/RingStats/Resources/ring-stats-logo.svg` | In-app split-ring mark | Maintainer-designed Ring Stats vector, finalized in the project Figma file |
| `Sources/RingStats/Resources/Assets.xcassets/RingStatsMenuIcon.imageset/` | 17 pt menu-bar template icon | Raster exports of the project split-ring vector at 1× and 2× |
| `native/AppIcon.svg` and `AppIcon.appiconset/` | Finder/Spotlight application icon | Project-owned derivative of the Ring Stats identity |
| `LandscapeBackground.png` | Bundled Landscape theme | Project-owned generated landscape created for Ring Stats; no Oura, person, or product imagery |
| `.github/assets/ring-stats-banner.*` | README identity banner | Maintainer-provided export from the project Figma file |
| `.github/assets/ring-stats-themes-v2.png` | README theme showcase | Maintainer-provided Figma export of reconstructed Ring Stats states |

The numeric health values in the README theme showcase are synthetic fixtures
chosen to demonstrate layout. They are not a user's Oura data and should not be
used as product, health, or API evidence.

SF Symbols referenced by name in Swift source are supplied and rendered by
macOS. They are not bundled project logos. Apple permits SF Symbols inside
interfaces subject to Apple's license and platform guidance; do not repurpose
them as an application or project identity.

When adding assets, document creator/source, license or ownership, generation
method, material edits, and whether displayed data is synthetic. Never commit
private health screenshots or third-party brand assets without permission.
