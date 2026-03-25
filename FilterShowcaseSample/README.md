# Filter Showcase Sample 2

`FilterShowcaseSample2` is a live camera-based playground for `VideoProcessingTwo`.

## What It Demonstrates

- Full-screen live camera rendering using `CameraSource` + `VideoScene`.
- Slide-up translucent control panel over the camera feed.
- Filter browsing with parameter sliders.
- Real-time parameter updates while the camera is running.

## Main Files

- `FilterShowcaseSample/ContentView.swift`
  - Full-screen `MetalView` camera preview
  - Sliding controls panel with search, selection, and parameter UI
- `FilterShowcaseSample/FilterShowcaseViewModel.swift`
  - Camera setup (`CameraManager` / `CameraSource`)
  - Filter catalog
  - Live application of current filter and parameter values

## Notes

- The filter list includes all concrete filter types in `VideoProcessingTwo/Sources/Filters` (excluding utility base/protocol files).
