# VideoProcessingTwo Samples

A collection of sample iOS projects demonstrating the capabilities of the VideoProcessingTwo framework.

## Sample Projects

### AnimatedFiltersSample
Demonstrates real-time filter animations applied to video playback. Shows how to create animated filters with customizable parameters that change over time.

### HandPoseAnimationSample
Uses Vision framework hand pose detection to drive interactive animations and effects. The app detects hand positions and uses them to control blur and brightness filters in real-time. Also demonstrates audio-driven animations for visual feedback.

### MultiLayerSample
Shows how to composite multiple video and image layers together with text overlays. Demonstrates layer positioning, timing, GIF playback, and filter application across multiple layers.

### RealtimeCameraSample
Applies real-time filters to live camera feed using the CameraSource pattern. Includes selectable filters (Gaussian Blur, Crystallize, Color Adjustment, Glitch Effect) with adjustable intensity.

### VideoOverlaySample
Composites photo and GIF overlays on top of video with adjustable opacity, position, and scale. Demonstrates how to create dynamic overlays with fade filters and export the composed result.

## Key Concepts

- **CameraSource**: Integrates camera capture sessions directly into VideoScene rendering pipelines
- **Layers & Groups**: Organize visual elements hierarchically for complex compositions
- **Filters**: Apply real-time effects to camera feeds and video playback
- **VideoScene**: The main composition object that manages rendering and effects
- **Surface**: Represents visual content (video, image, camera feed, text) positioned within a layer
