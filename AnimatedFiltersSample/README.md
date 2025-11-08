# Animated Filters Sample

This sample demonstrates the **FilterAnimator** system in VideoProcessingTwo, which allows you to animate filter parameters over time.

## Features

- **5 different animation presets** showcasing various effects
- **Time-based parameter interpolation** using FilterAnimator
- **Multiple concurrent animations** on the same video
- **Linear interpolation** with TweenFunctionProvider
- **Real-time progress tracking** during export

## Animation Types

### Linear Interpolation (Basic)

#### 1. Fade In/Out
Demonstrates basic opacity animation:
- Fades in from 0% to 100% over first 2 seconds
- Fades out from 100% to 0% over last 2 seconds
- Uses `Fade` filter with two `FilterAnimator` instances
- Uses `LinearFunction()` for interpolation

#### 2. Animated Blur
Shows animated blur radius:
- Blur increases from 0 to 30 pixels at midpoint
- Blur decreases back to 0 by the end
- Uses `GaussianBlur` filter with radius animation

#### 3. Color Pulse
Demonstrates repeating color animations:
- Saturation pulses between 1.0x and 2.0x
- 3-second cycles that repeat throughout video
- Uses `ColorAdjustment` filter with multiple animators

#### 4. Zoom In/Out
Shows scale animation:
- Zooms from 1.0x to 1.5x at midpoint
- Zooms back to 1.0x by the end
- Uses `Scale` filter with scale parameter animation

#### 5. Combined Effects
Demonstrates multiple animations together:
- Fade in/out
- Zoom in/out
- Brightness pulse
- Shows how multiple filters can be animated simultaneously

### Bezier Curve Interpolation (Advanced)

#### 6. Bezier Ease
Smooth ease curve using multi-point bezier path:
- Uses `BezierPathTweenFunction.easeInOut` preset
- Demonstrates 2-point bezier curve with control handles
- Creates smooth acceleration/deceleration
- Applied to fade effect

#### 7. Multi Bounce
Organic bounce effect using complex bezier path:
- Uses `BezierPathTweenFunction.multiBounce` preset
- 5-point bezier curve simulating multiple bounces
- Scale animation from 0.5x to 1.0x
- Shows overshoot with control points beyond normal range

#### 8. Wave Effect
Oscillating wave pattern:
- Uses `BezierPathTweenFunction.wave` preset
- 5-point bezier curve creating wave pattern
- Applied to brightness adjustment
- Demonstrates repeating patterns with bezier curves

#### 9. Three Step
Stepped animation with pauses:
- Uses `BezierPathTweenFunction.threeStep` preset
- 4-point bezier curve with flat segments
- Pauses at 33% and 66% progress
- Control handles create flat plateaus
- Applied to fade effect

## How It Works

### FilterAnimator Setup

```swift
let fadeInAnimator = FilterAnimator(
    type: .SingleValue,              // Animating a single double value
    animationProperty: .fade,        // Which property to animate
    startValue: 0.0,                 // Starting value
    endValue: 1.0,                   // Ending value
    startTime: 0.0,                  // Start at beginning
    endTime: 2.0,                    // End at 2 seconds
    tweenFunctionProvider: LinearFunction()  // Linear interpolation
)

let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeInAnimator])
scene.group.filters.append(fadeFilter)
```

### Animation Types

FilterAnimator supports three animation types:

1. **SingleValue** - Animate double values (opacity, blur radius, brightness, etc.)
2. **Point** - Animate CGPoint values (positions)
3. **Rect** - Animate CGRect values (crop areas, masks)

### Filter Properties

Available filter properties for animation:
- `.fade` - Opacity (0.0 to 1.0)
- `.radius` - Blur radius (pixels)
- `.scale` - Scale factor
- `.rotation` - Rotation angle
- `.translation` - Position offset
- `.brightness` - Brightness adjustment
- `.contrast` - Contrast adjustment
- `.saturation` - Saturation adjustment
- `.intensity` - Effect intensity

### Tween Functions

The framework supports multiple interpolation methods:

#### Linear Interpolation
```swift
LinearFunction() // Straight line from start to end
```

#### Bezier Path Curves (Multi-Point)
Create complex curves with multiple points and control handles:

```swift
// Custom 3-point curve with overshoot
let customCurve = BezierPathTweenFunction(points: [
    BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.2, y: 0)),
    BezierPoint(x: 0.5, y: 0.7,
                controlPoint1: CGPoint(x: 0.3, y: 0.9),  // Pull up
                controlPoint2: CGPoint(x: 0.7, y: 0.9)), // Pull up
    BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.8, y: 1))
])
```

**BezierPoint Structure:**
- `x`, `y` - The point coordinates (x should be 0-1 for animation timing)
- `controlPoint1` - Control handle before this point (affects incoming curve)
- `controlPoint2` - Control handle after this point (affects outgoing curve)
- Helper init: `BezierPoint(x:y:controlOffset:)` creates symmetric handles

**Preset Curves:**
- `BezierPathTweenFunction.linear` - Straight line
- `BezierPathTweenFunction.easeInOut` - Smooth ease
- `BezierPathTweenFunction.sCurveWithBump` - S-curve with middle overshoot
- `BezierPathTweenFunction.threeStep` - Three distinct steps
- `BezierPathTweenFunction.multiBounce` - Multiple bounces
- `BezierPathTweenFunction.wave` - Oscillating wave

#### Simple Cubic Bezier (CSS-Style)
Single cubic bezier segment (like CSS `cubic-bezier()`):

```swift
// CSS ease-in-out equivalent
let easeInOut = CubicBezierTweenFunction(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0)
```

**Presets:**
- `CubicBezierTweenFunction.ease`
- `CubicBezierTweenFunction.easeIn`
- `CubicBezierTweenFunction.easeOut`
- `CubicBezierTweenFunction.easeInOut`

#### Custom Tween Functions
Implement `TweenFunctionProvider` for custom math:

```swift
class SineWaveTween: TweenFunctionProvider {
    func tweenValue(input: Double) -> Double {
        // Sine wave oscillation
        return 0.5 + 0.5 * sin(input * .pi * 4)
    }
}

class ElasticTween: TweenFunctionProvider {
    func tweenValue(input: Double) -> Double {
        // Elastic bounce effect
        let c4 = (2 * .pi) / 3
        return input == 0 ? 0 :
               input == 1 ? 1 :
               pow(2, -10 * input) * sin((input * 10 - 0.75) * c4) + 1
    }
}
```

### Creating Complex Bezier Curves

**Example: Heartbeat Pattern**
```swift
let heartbeat = BezierPathTweenFunction(points: [
    BezierPoint(x: 0, y: 0),
    // First beat
    BezierPoint(x: 0.15, y: 0.8,
                controlPoint1: CGPoint(x: 0.1, y: 0.1),
                controlPoint2: CGPoint(x: 0.2, y: 0.1)),
    // Dip
    BezierPoint(x: 0.25, y: 0.4,
                controlPoint1: CGPoint(x: 0.2, y: 0.6),
                controlPoint2: CGPoint(x: 0.3, y: 0.6)),
    // Second beat
    BezierPoint(x: 0.35, y: 1.2,  // Overshoot!
                controlPoint1: CGPoint(x: 0.3, y: 0.5),
                controlPoint2: CGPoint(x: 0.4, y: 0.5)),
    // Return to baseline
    BezierPoint(x: 0.5, y: 0.5,
                controlPoint1: CGPoint(x: 0.4, y: 0.8),
                controlPoint2: CGPoint(x: 0.6, y: 0.5)),
    // Flat line
    BezierPoint(x: 1, y: 0.5,
                controlPoint1: CGPoint(x: 0.9, y: 0.5))
])
```

**Example: Stepped Ease**
```swift
let steps = BezierPathTweenFunction(points: [
    BezierPoint(x: 0, y: 0,
                controlPoint2: CGPoint(x: 0.1, y: 0)),
    // Flat at 0.25
    BezierPoint(x: 0.25, y: 0.25,
                controlPoint1: CGPoint(x: 0.2, y: 0.25),
                controlPoint2: CGPoint(x: 0.3, y: 0.25)),
    // Flat at 0.5
    BezierPoint(x: 0.5, y: 0.5,
                controlPoint1: CGPoint(x: 0.45, y: 0.5),
                controlPoint2: CGPoint(x: 0.55, y: 0.5)),
    // Flat at 0.75
    BezierPoint(x: 0.75, y: 0.75,
                controlPoint1: CGPoint(x: 0.7, y: 0.75),
                controlPoint2: CGPoint(x: 0.8, y: 0.75)),
    BezierPoint(x: 1, y: 1,
                controlPoint1: CGPoint(x: 0.9, y: 1))
])
```

**Tips for Designing Curves:**
- X values should increase monotonically (each point's x > previous x)
- First point should have x=0, last point should have x=1
- Y values can go beyond 0-1 for overshoot/bounce effects
- Control points before/after create smooth tangents at points
- Symmetric control offsets create smooth S-curves
- Asymmetric controls create sharp corners or direction changes

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode
2. Select **File → New → Project**
3. Choose **iOS → App**
4. Product Name: `AnimatedFiltersSample`
5. Interface: **SwiftUI**
6. Language: **Swift**

### 2. Add Source Files

Copy these files to your project:
- `AnimatedFiltersSampleApp.swift`
- `ContentView.swift`
- `AnimationViewModel.swift`

### 3. Add VideoProcessingTwo Dependency

1. Select your project in the navigator
2. Select the **AnimatedFiltersSample** target
3. Go to **Frameworks, Libraries, and Embedded Content**
4. Add the local VideoProcessingTwo package

### 4. Add Sample Video

Add `mountain.mp4` (or any video) to the project bundle.

### 5. Run the App

1. Select iOS device or simulator
2. Build and run (`Cmd+R`)
3. Select an animation type
4. Tap "Export with Animation"
5. Watch progress bar
6. Play the exported video

## Code Structure

### AnimationViewModel

The core logic for creating animated scenes:

```swift
private func addFadeInOutAnimation(to scene: Scene, duration: Double) {
    // Create animator for fade in
    let fadeInAnimator = FilterAnimator(...)

    // Create animator for fade out
    let fadeOutAnimator = FilterAnimator(...)

    // Create filter with both animators
    let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeInAnimator, fadeOutAnimator])

    // Add to scene
    scene.group.filters.append(fadeFilter)
}
```

### How Animations Execute

During export, for each frame:

1. `scene.group.renderGroup(frameTime: time)` is called
2. For each filter, the framework checks its `filterAnimators`
3. Each animator calculates the interpolated value for current time:
   ```swift
   let tweenedValue = animator.tweenValue(time: frameTime)
   filter.updateFilterValue(filterProperty: animator.animationProperty, value: tweenedValue)
   ```
4. Filter applies with the animated value
5. Result is composited

This happens automatically in `Group.renderGroup()`:
```swift
for filter in filters {
    for animator in filter.filterAnimators {
        let tweenedValue = animator.tweenValue(time: frameTime)
        filter.updateFilterValue(filterProperty: animator.animationProperty, value: tweenedValue)
    }
    outputImage = filter.filterContent(image: outputImage, ...)
}
```

## Extending the Sample

### Add New Animation Type

1. Add case to `AnimationType` enum
2. Create animation method in `AnimationViewModel`
3. Add switch case in `createAnimatedScene()`
4. Add description in `descriptionForAnimation()`

### Add Custom Tween Function

```swift
class EaseInOutFunction: TweenFunctionProvider {
    func tweenValue(input: Double) -> Double {
        // Cubic ease in/out
        if input < 0.5 {
            return 4 * input * input * input
        } else {
            let f = (2 * input) - 2
            return 0.5 * f * f * f + 1
        }
    }
}
```

### Animate Multiple Properties

```swift
// Create separate animators for different properties
let brightnessAnimator = FilterAnimator(
    type: .SingleValue,
    animationProperty: .brightness,
    startValue: 0.0,
    endValue: 0.5,
    startTime: 0.0,
    endTime: duration,
    tweenFunctionProvider: LinearFunction()
)

let saturationAnimator = FilterAnimator(
    type: .SingleValue,
    animationProperty: .saturation,
    startValue: 1.0,
    endValue: 2.0,
    startTime: 0.0,
    endTime: duration,
    tweenFunctionProvider: LinearFunction()
)

// Pass both animators to filter
let colorFilter = ColorAdjustment(
    brightness: 0.0,
    contrast: 1.0,
    saturation: 1.0,
    filterAnimators: [brightnessAnimator, saturationAnimator]
)
```

## Performance Notes

- Animations have no additional performance cost beyond the filters themselves
- The interpolation calculation is negligible compared to image processing
- Multiple animators can run concurrently without issues
- Export speed depends on filter complexity, not animation complexity

## Requirements

- iOS 15.0+
- Xcode 14.0+
- VideoProcessingTwo library

## Next Steps

- Try creating custom tween functions for different easing curves
- Combine multiple animated filters for complex effects
- Animate position and scale for "Ken Burns" style effects
- Create animated transitions between scenes
