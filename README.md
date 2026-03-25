# VideoProcessingTwo Samples

Standalone iOS sample apps for exploring the `VideoProcessingTwo` framework.

Main framework repo: [interrobangdev/VideoProcessingTwo](https://github.com/interrobangdev/VideoProcessingTwo)

## Current Samples

### AnimatedFiltersSample
Shows how to animate filter parameters over time with `FilterAnimator`, including fade, blur, zoom, color pulse, preset bezier curves, and a custom bezier curve editor.

### FilterShowcaseSample
Live camera filter playground with a searchable filter and style catalog, slide-up controls, parameter sliders, and front/back camera switching.

### FourVideoGridSample
Builds a 2x2 video composition and turns it into an interactive sliding puzzle, with shuffle, solve, and photo library video selection support.

### HandPoseAnimationSample
Uses live hand-pose detection and optional audio input to drive real-time visual effects, on-screen metrics, and recording/export of the processed camera feed.

### MultiLayerSample
Demonstrates layered composition with timed video clips, still images, GIF overlays, and text arranged in a single `VideoScene`.

### RealtimeCameraSample
Applies selectable filters directly to a live camera feed using `CameraSource`, including blur, crystallize, color adjustment, and glitch effects.

### VideoFilter
Metal-backed filter preview app for testing the framework's filter catalog on a looping video, with live parameter updates, export, and share/save flow.

### VideoOverlaySample
Composites photo and GIF overlays on top of a video with adjustable position, scale, and opacity, then exports the finished result.

## Repo Notes

- Each sample is a standalone Xcode project in its own folder.
- Several sample folders include their own `README.md` with deeper setup or implementation notes.

## Core Concepts Used Across Samples

- **VideoScene**: The main composition object for arranging sources and effects.
- **Layers and Groups**: Structure video, image, GIF, text, and camera content into composited scenes.
- **Filters**: Apply real-time and export-time effects to camera feeds and prerecorded media.
- **CameraSource**: Connect live camera capture to the rendering pipeline.
- **ExportManager**: Render a composed scene out to a movie file.
