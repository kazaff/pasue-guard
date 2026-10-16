# Local image backgrounds

`PauseGuardImages` is a macOS 14+ library using Foundation, ImageIO, CoreGraphics,
CryptoKit and Accelerate. It does not contact services, generate images, or access
screens. Original imported bytes remain local and unchanged; orientation is applied
when creating thumbnails and rendered tiles.

## Storage and threading

- `try AssetLibrary(rootURL: URL)` creates/loads a version-1 `library.json` and
  exposes `rootURL`, `assets: [ImageAsset]`, and `themes: [BreakTheme]` snapshots.
  Use one instance on a single serial executor. Its synchronous disk and decode
  operations should run off the main actor. The class is intentionally not Sendable.
- `try library.importImages([URL]) -> [ImageAsset]` copies valid PNG/JPEG/HEIC/HEIF
  originals and writes upright PNG thumbnails (longest edge ≤512). A new enabled
  `Default` theme owns imports until themes are configured. Byte-identical originals
  reuse the same ID; a batch returns each imported/reused asset once. Unreadable,
  corrupt, unsupported, empty, >100 MiB, or unsafe-dimension items are skipped while
  later items continue. Storage/metadata failures throw. Earlier successful items
  remain persisted if a later storage operation fails.
- Source dimensions are limited to 32,768 per axis and 64 megapixels before decode.
  ImageIO thumbnail APIs receive bounded pixel sizes and cache=false options; no
  full-resolution `CGImageSourceCreateImageAtIndex` is used in production.
- `try library.removeImage(id: UUID)` atomically removes all metadata/theme references,
  then deletes original and thumbnail. A failed file deletion can leave an orphan;
  references are already safe. Unknown IDs are ignored.
- `try library.saveThemes([BreakTheme])` atomically replaces themes. Duplicate theme
  IDs retain the first; duplicate/missing image references are removed. Imports append
  to the generated Default theme when it still exists, preserving its enabled state.
  Custom themes explicitly control membership.
- Unknown metadata versions and corrupt metadata throw rather than overwriting data.

`ImageAsset` is Codable/Sendable/Equatable/Identifiable with immutable `id: UUID`,
`fileName: String`, `width: Int`, `height: Int` (upright dimensions), and
`thumbnailName: String`. Both filenames are relative to `rootURL`.

`BreakTheme` is Codable/Sendable/Equatable/Identifiable with mutable `id: UUID`,
`name: String`, `enabled: Bool` (default true), `imageIDs: [UUID]`, and
`layoutMode: LayoutMode` (default hero). `LayoutMode` is a Codable string enum:
`hero`, `grid`, `collage`, `cinematic`, `minimal`, `random`.
`LayoutMode.concreteCases` contains the five renderable layouts; `allCases` includes
random for preference controls.

## Selecting and rendering

```swift
let next = ImageSelector.select(themes: library.themes,
                                assets: library.assets, previous: previous)
// nil means show the built-in dark background, with no selected photos.
let selection = next ?? Selection(layoutMode: .hero, assets: [])
let image = try Compositor.render(selection: selection,
                                  size: CGSize(width: 1920, height: 1080),
                                  libraryURL: library.rootURL)
```

Selection is Sendable/Equatable with `themeID: UUID?`, concrete `layoutMode`, and
`assets: [ImageAsset]`. Its initializer defaults themeID to nil. Selection filters
missing references, considers enabled themes only, and chooses up to four unique
assets. It avoids the previous primary image when another eligible image exists,
then avoids the previous theme where possible. Random preferences choose a concrete
layout different from the previous layout. No enabled usable theme returns nil.
For single-image mode, construct a copy with `assets: Array(next.assets.prefix(1))`;
all five layouts support one image.

`Compositor.render(selection:size:libraryURL:)` is synchronous and stateless, safe
on a background executor. Size is in pixels, positive and finite; output is uniformly
scaled to a longest edge of 4096 (integer dimensions round down). Each tile is
ImageIO-downsampled before color processing. Blur tiles decode to ≤1024, sharp tiles
to ≤4096. Tone processing and CPU box blur work without Metal/Core Image availability.
Missing/corrupt files are skipped, yielding an opaque dark gradient fallback if all
are missing. A direct `.random` render falls back to hero; use the selector to randomize.
Layouts use full-height hero, four-cell grid, framed rotated collage, letterboxed
cinematic, and blurred negative-space minimal compositions. All have a dark feathered
center reserved for a white countdown. The compositor does not draw countdown text.

`BackgroundCache(maximumCount: Int = 8, maximumBytes: Int = 128 * 1024 * 1024)` is
thread-safe and uses immutable CGImages. Caller budgets can only lower these ceilings.
`image(forKey: String) -> CGImage?` refreshes recency;
`insert(_: CGImage, forKey: String)` evicts least-recently-used entries using actual
`bytesPerRow * height`; oversized entries are not retained. `removeAll()` invalidates
all entries. Build keys from selection, library revision and pixel size; invalidate
on edits/removals. Cache limits govern retained outputs, not transient render buffers.

## Validation

`bash Scripts/test.sh --filter PauseGuardImagesTests` runs local PNG/JPEG fixtures,
EXIF-thumbnail checks, five distinct pixel outputs, white-center contrast, one-photo
fallback, dimension/file-size limits, theme/selection behavior and LRU ceilings.
`PAUSEGUARD_PREVIEW_DIR=.build/previews` exports five preview PNGs during the layout
test. No user photos are needed.

HEIC import uses the platform ImageIO decoder, but this environment's HEIC fixture
encoder fails to finalize (IOSurface/virtualization diagnostics). HEIC decode has
therefore **not been exercised by a generated fixture here**. The optional fixture
check is disabled by default to avoid repeatedly invoking the unavailable encoder;
run `PAUSEGUARD_TEST_HEIC_ENCODER=1 bash Scripts/test.sh --filter testHEICImportWhenEncoderAvailable`
on a machine with a working HEIC encoder. It imports and checks upright thumbnail
sizes only when encoding succeeds.
