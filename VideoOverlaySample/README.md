# Video Overlay Sample

This sample demonstrates how to overlay photos and animated GIFs onto video using the **VideoProcessingTwo** library. It processes videos frame-by-frame, applies overlays, and exports a new video file with the composited result.

## Features

- Load videos from files
- Overlay static images (photos) on video
- Overlay animated GIFs on video with synchronized playback
- Adjustable position (X/Y coordinates) for both overlays
- Scale control for both overlays
- Opacity/transparency control
- Export processed video to new file
- Real-time progress indicator during export
- Built-in video player to preview results

## Setup Instructions

### 1. Create a New Xcode Project

1. Open Xcode
2. Select **File → New → Project**
3. Choose **iOS → App**
4. Fill in the project details:
   - Product Name: `VideoOverlaySample`
   - Interface: **SwiftUI**
   - Language: **Swift**
5. Save the project in the `VideoOverlaySample` folder (the one containing this README)

### 2. Add the Source Files

The following source files are already created in the `VideoOverlaySample` subfolder:

- `VideoOverlaySampleApp.swift` - Main app entry point
- `ContentView.swift` - Video player UI with overlay controls
- `OverlayViewModel.swift` - Video playback and compositing logic

When you create the Xcode project, replace the generated files with these existing files, or delete the generated files and add the existing files to your project.

### 3. Add the VideoProcessingTwo Dependency

1. In Xcode, select your project in the navigator
2. Select the **VideoOverlaySample** target
3. Go to the **General** tab
4. Scroll down to **Frameworks, Libraries, and Embedded Content**
5. Click the **+** button
6. Click **Add Other... → Add Package Dependency...**
7. Enter the path to your local VideoProcessingTwo package:
   ```
   file:///Users/jakegundersen/Repos/VideoProcessingTwo
   ```
   (Or use the relative path: `../../VideoProcessingTwo`)
8. Click **Add Package**
9. Select **VideoProcessingTwo** and click **Add Package**

### 4. Prepare Sample Assets

You'll need to prepare the following assets to test the app:

#### Video File
- Any `.mp4`, `.mov`, or `.m4v` video file
- Recommended: 10-30 seconds in length
- Place in a location accessible via the file picker

#### Photo File
- Any `.jpg`, `.png`, or `.heic` image file
- This will be composited on top of the video
- Recommended: Square or portrait orientation works best

#### GIF File
- Any animated `.gif` file
- The GIF will loop and play synchronized with the video
- Recommended: Small/medium size GIFs work best

**Note**: The app uses file pickers, so you don't need to add these to the Xcode project. Just have them ready on your device or simulator.

### 5. Run the App

1. Select an iOS device or simulator as your run destination
   - Both simulator and physical device will work
2. Click the **Run** button or press `Cmd+R`
3. Use the file picker buttons to load:
   - A video file (required)
   - A photo overlay (optional - uses placeholder if not loaded)
   - A GIF overlay (optional - uses placeholder if not loaded)
4. Adjust overlay positions, scales, and opacity using the sliders
5. Tap **"Export Video with Overlays"** to process the video
6. Watch the progress bar as the video is processed frame-by-frame
7. When complete, tap **"Play Video"** to preview the result

## How It Works

### Video Processing Pipeline

The app uses VideoProcessingTwo's Scene/Layer/Surface architecture:

1. **Scene** - Represents the video composition with duration and size
2. **Layers** - Each layer contains one or more surfaces (video, photo, GIF)
3. **Surfaces** - Define the source content and how it's positioned/scaled
4. **Groups** - Organize layers and apply filters (like opacity via Fade filter)
5. **ExportManager** - Handles the export process with progress tracking

### Creating a Scene

```swift
let scene = VideoScene(duration: videoDuration, frameRate: 30.0, size: videoSize)

// Add video as base layer
scene.addAsset(
    atLayerIndex: LayerObjectIndex(groupIndices: [], layerIndex: 0),
    type: .video,
    frame: videoFrame,
    assetURL: videoURL
)

// Add photo overlay in a group with opacity filter
let surface = Surface(source: photoSource, frame: photoFrame, rotation: 0.0)
let layer = Layer(surfaces: [surface])
let fadeFilter = Fade(fade: opacity, filterAnimators: [])
let group = Group(groups: [], layers: [layer], filters: [fadeFilter], mask: nil)
scene.group.groups.append(group)
```

### GIF Handling

VideoProcessingTwo's `GIFImageSource` automatically handles frame extraction and timing:

```swift
let gifData = try Data(contentsOf: url)
let gifImage = GIFImage(gifData: gifData)
let gifSource = GIFImageSource(image: gifImage)
```

### Exporting

The ExportManager handles all the heavy lifting:

```swift
ExportManager.shared.exportScene(
    scene: scene,
    outpuURL: outputURL,
    progress: { _, progress in
        self.exportProgress = progress
    },
    completion: { success in
        self.isExporting = false
    }
)
```

## Project Structure

```
VideoOverlaySample/
├── README.md (this file)
└── VideoOverlaySample/
    ├── VideoOverlaySampleApp.swift
    ├── ContentView.swift
    └── OverlayViewModel.swift
```

## Requirements

- iOS 15.0+
- Xcode 14.0+
- VideoProcessingTwo library

## Troubleshooting

### Export Fails
- Ensure the video file format is supported (.mp4, .mov, .m4v)
- Check that you have enough free storage space
- Look for error messages displayed in the app
- Check the Xcode console for detailed error logs

### Overlays Not Showing in Exported Video
- Make sure you've loaded both a video and the overlay files before exporting
- Check that opacity is not set to 0%
- Verify the position is within the visible area (0-1 range)
- If using placeholders, they will appear as colored rectangles

### GIF Not Animating in Exported Video
- Confirm the file is actually an animated GIF (not a static image)
- Check that GIFImageSource successfully loaded the file
- Verify the GIF has multiple frames

### Slow Export Speed
- Large/high resolution videos take longer to process
- 4K videos may take several minutes
- Each frame must be processed individually
- This is normal for frame-by-frame processing

### Video Player Not Opening
- Ensure export completed successfully (100% progress)
- Check that no errors occurred during export
- Try exporting again if the first attempt failed

## Next Steps

- Add ability to save exported video to Photos library
- Implement drag-and-drop for positioning overlays
- Add rotation controls for overlays
- Support multiple overlay layers (not just photo + GIF)
- Add filter effects to overlays or video
- Implement keyframe animation for overlay properties (position changes over time)
- Add audio track preservation/mixing
- Support for text overlays with custom fonts
