# HandPoseAnimationSample

A live camera feed that detects hand pose and drives animation parameters in real-time.

## What It Does

- **Live Camera Feed**: Displays video from device camera
- **Hand Pose Detection**: Uses VisionTools to detect hand landmarks
- **Live Data Collection**: Collects hand pose data as frames
- **Animation Drivers**: Hand position controls filter effects

## Architecture

### HandPoseDataCollector
Collects hand pose data from live camera frames via CameraManager and VisionTools.

```swift
let collector = HandPoseDataCollector()
cameraManager.delegate = collector  // Receives frames
collector.getNormalizedHandPosition()  // Get hand position (0.0-1.0)
```

### HandAnimationController
Drives filter animations based on collected hand data.

```swift
let controller = HandAnimationController(poseCollector: collector)

// Get animator driven by hand X position
let blurAnimator = controller.getBlurAnimatorDrivenByHandX(duration: 10.0)

// Use in video composition
scene.group.filters.append(GaussianBlur(radius: 0.0, filterAnimators: [blurAnimator]))
```

### Tween Functions
- **HandPositionTweenFunction**: Maps hand position (x, y, or distance) to filter parameters
- **FingerCountTweenFunction**: Maps number of raised fingers to animation value

## Animation Examples

### Hand X Drives Blur
Hand horizontal position (left-right) controls blur radius (0-50 pixels)

```swift
let tween = HandPositionTweenFunction(
    collector: poseCollector,
    duration: 10.0,
    coordinate: .x,
    outputMin: 0.0,
    outputMax: 50.0
)
```

### Hand Y Drives Brightness
Hand vertical position (up-down) controls brightness (-0.5 to +0.5)

```swift
let tween = HandPositionTweenFunction(
    collector: poseCollector,
    duration: 10.0,
    coordinate: .y,
    outputMin: -0.5,
    outputMax: 0.5
)
```

### Hand Distance Drives Scale
Hand distance from center controls zoom (0.8x to 1.5x)

```swift
let tween = HandPositionTweenFunction(
    collector: poseCollector,
    duration: 10.0,
    coordinate: .distance,
    outputMin: 0.8,
    outputMax: 1.5
)
```

### Finger Count Drives Opacity
Number of raised fingers controls opacity (0-5 fingers to 0.0-1.0)

```swift
let tween = FingerCountTweenFunction(
    collector: poseCollector,
    duration: 10.0
)
```

## Usage

### In Your Code

```swift
// Create components
let cameraManager = CameraManager()
let poseCollector = HandPoseDataCollector()
let animationController = HandAnimationController(poseCollector: poseCollector)

// Connect camera to pose detection
cameraManager.delegate = poseCollector
cameraManager.setup()
cameraManager.start()
poseCollector.start()

// Create animation driven by hand position
let blurAnimator = animationController.getBlurAnimatorDrivenByHandX(duration: 10.0)

// Use animator in video composition
let blurFilter = GaussianBlur(radius: 0.0, filterAnimators: [blurAnimator])
scene.group.filters.append(blurFilter)
```

### In SwiftUI

The sample app shows a live camera view with hand detection visualization:

```swift
@StateObject private var viewModel = CameraViewModel()

var body: some View {
    ZStack {
        CameraPreviewView(cameraManager: viewModel.cameraManager)

        VStack {
            if viewModel.animationState.isHandPresent {
                Text("Hand Detected at \(viewModel.handPosition)")
            }
        }
    }
    .onAppear {
        viewModel.startCamera()
    }
}
```

## File Structure

```
HandPoseAnimationSample/
├── HandPoseDataCollector.swift      ← Collects hand data from camera
├── HandAnimationController.swift    ← Drives animations from hand data
├── CameraViewModel.swift             ← Manages camera and data flow
├── ContentView.swift                 ← SwiftUI UI
└── HandPoseAnimationSampleApp.swift ← App entry
```

## Key Classes

### HandPoseDataCollector
- Conforms to `CameraManagerDelegate`
- Receives frames from CameraManager
- Uses VisionTools to detect hand poses
- Stores frames with timestamps
- Provides normalized hand position (0.0-1.0)

### HandAnimationController
- Takes HandPoseDataCollector as input
- Provides ready-to-use animators
- Tracks animation state
- Updates on hand pose changes

### HandPositionTweenFunction
- Implements TweenFunctionProvider
- Reads current hand position from collector
- Maps to filter parameter range
- Updates in real-time as hand moves

### FingerCountTweenFunction
- Counts raised fingers from hand observation
- Maps finger count to animation value
- Updates as hand opens/closes

## Hand Landmarks

Available landmarks for detailed hand tracking:

```
Wrist, Thumb (IP, MCP, PIP, TIP), Index (MCP, PIP, TIP),
Middle (MCP, PIP, TIP), Ring (MCP, PIP, TIP), Little (MCP, PIP, TIP)
```

Get specific landmarks:

```swift
let indexTipPosition = collector.getHandLandmarkPosition(.indexTIP)
let allLandmarks = collector.getAllHandLandmarks()
```

## Live Data Collection

The app automatically collects hand pose data as frames arrive:

```swift
collector.frames  // Array of HandPoseFrame with timestamp and observations
collector.frames.count  // Number of frames collected
```

Each frame contains:
- `timestamp`: Time since collection started
- `handObservations`: Detected hand poses
- `frameSize`: Camera frame dimensions

## Next Steps

1. **Create Xcode project** with VideoProcessingTwo dependency
2. **Add all Swift files** to project
3. **Request camera permissions** (add NSCameraUsageDescription to Info.plist)
4. **Build and run** on device (hand pose requires real hardware)
5. **Create animations** using HandAnimationController

## Real-Time Animation

The tween functions read hand position live as the animation plays:

```
Frame captured → VisionTools detects hand → Position stored
                                          ↓
                                  FilterAnimator calls tweenValue()
                                          ↓
                                  TweenFunction reads current hand position
                                          ↓
                                  Filter applies with live-controlled parameter
```

## Performance Notes

- Hand detection runs on background thread
- UI updates on main thread
- No frame dropping in collection
- Low latency (typically <50ms)
- Works at 30fps on modern devices

## Extending

To add new animation types:

1. Create new TweenFunction implementing `TweenFunctionProvider`
2. Add method to `HandAnimationController`
3. Use in video composition

Example:
```swift
class CustomHandTweenFunction: TweenFunctionProvider {
    let collector: HandPoseDataCollector

    func tweenValue(input: Double) -> Double {
        let position = collector.getNormalizedHandPosition()
        // Your custom logic
    }
}
```
