# Filter Showcase Sample

`FilterShowcaseSample` is a playground app for `VideoProcessingTwo` filters and style recipes.

## What It Demonstrates

- Interactive preview playback with `SceneVideoComposition`
- A broad filter catalog spanning core filters and migrated Shimmeo-era filters
- Style preset playback using `ShimmeoStyleRecipeFactory`
- Live parameter tuning via an auto-generated slider panel

## Main Files

- `FilterShowcaseSample/ContentView.swift`
  - UI for mode switching (`Filters` vs `Style Presets`), search, picker, and parameter controls.
- `FilterShowcaseSample/FilterShowcaseViewModel.swift`
  - Builds filter/style catalogs.
  - Rebuilds the composition when selection/parameters change.
  - Defines filter parameter metadata and filter construction closures.

## Notes

- The sample uses bundled video (`download.mov`, fallback `mountain.mp4`).
- Some filters are time-varying (pulse, jitter, twirl) and animate continuously.
- Style presets are loaded from `ShimmeoStyleRecipeFactory.supportedStorageNames`, including newly migrated entries.
