# Filter Showcase Sample 2

`FilterShowcaseSample2` is a live camera-based playground for `VideoProcessingTwo`.

## What It Demonstrates

- Full-screen live camera rendering using `CameraSource` + `VideoScene`.
- Slide-up translucent control panel over the camera feed.
- Two browsing modes:
  - Individual filters (with parameter sliders)
  - Style recipes from `ShimmeoStyleRecipeFactory`
- Real-time parameter updates while the camera is running.

## Main Files

- `FilterShowcaseSample/ContentView.swift`
  - Full-screen `MetalView` camera preview
  - Sliding controls panel with search, selection, and parameter UI
- `FilterShowcaseSample/FilterShowcaseViewModel.swift`
  - Camera setup (`CameraManager` / `CameraSource`)
  - Filter and recipe catalogs
  - Live application of current filter/recipe and parameter values

## Notes

- The filter list includes all concrete filter types in `VideoProcessingTwo/Sources/Filters` (excluding utility base/protocol files).
- Recipe mode includes all unique recipe storages resolved from `ShimmeoStyleRecipeFactory.supportedStorageNames`.
