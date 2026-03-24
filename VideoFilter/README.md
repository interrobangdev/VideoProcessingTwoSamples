# VideoFilter

`VideoFilter` is a Metal-backed sample app for trying the full `VideoProcessingTwo` filter catalog on a looping video clip.

## Features

- Uses `MovieReader` + `VideoScene.renderScene(...)` for live preview instead of `AVPlayer`
- Displays frames through `MetalView`
- Loads a bundled sample video on launch
- Imports a user-selected video with the system file picker
- Includes the full filter list from the live filter showcase
- Updates filter parameters live while the video continues to play
- Exports the currently filtered scene to a movie file
- Shares the exported file from the app

## Project Structure

- `VideoFilter/ContentView.swift` - Main UI for loading videos, choosing filters, and exporting
- `VideoFilter/VideoFilterViewModel.swift` - MovieReader-driven preview loop, live filter updates, and export flow
- `VideoFilter/mountain.mp4` - Bundled fallback video

## Notes

- The Xcode project references the local `VideoProcessingTwo` package at `../../../../../Repos/VideoProcessingTwo` from this checkout layout.
- Preview is intentionally rendered from decoded frames into `MetalView`, so filter changes appear immediately on the next rendered frame.
