# VideoFilter

`VideoFilter` is a focused sample app for trying `VideoProcessingTwo` filters on a loaded video clip.

## Features

- Loads a bundled sample video on launch
- Imports a user-selected video with the system file picker
- Loops the filtered preview continuously
- Presents a filter-showcase style menu with live parameter sliders
- Exports the currently filtered scene to a movie file
- Lets you preview or share the exported video after export completes

## Included Filters

- Original
- Gaussian Blur
- Color Adjustment
- Crystallize
- Bloom Glow
- Sepia
- Mirror
- Temporal Fade Atlas
- Heatmap Frame Offset Atlas

## Project Structure

- `VideoFilter/ContentView.swift` - Main UI for loading, previewing, and exporting
- `VideoFilter/VideoFilterViewModel.swift` - Filter catalog, player rebuilds, looping, and export flow
- `VideoFilter/mountain.mp4` - Bundled fallback video

## Notes

- The Xcode project references the local `VideoProcessingTwo` package at `../../../../../Repos/VideoProcessingTwo` from this worktree layout.
- Export output is written to a temporary `.mov` file and exposed through preview/share actions in the UI.
