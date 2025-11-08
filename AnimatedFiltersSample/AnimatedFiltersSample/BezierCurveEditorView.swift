//
//  BezierCurveEditorView.swift
//  AnimatedFiltersSample
//
//  Interactive bezier curve editor for creating custom animation curves
//

import SwiftUI

struct BezierCurveEditorView: View {
    @Binding var controlPoints: [CGPoint]
    let segmentCount: Int = 5

    @State private var draggingIndex: Int?
    @State private var draggingHandleIndex: Int?
    @State private var draggingIsOut: Bool = false

    // Bezier curve handles (control points for curve smoothness)
    // Each main point has an "in" and "out" control handle
    @State private var curveHandles: [(inHandle: CGPoint, outHandle: CGPoint)] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    // Vertical lines
                    for i in 0...10 {
                        let x = width * CGFloat(i) / 10
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }

                    // Horizontal lines
                    for i in 0...10 {
                        let y = height * CGFloat(i) / 10
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                // Draw the bezier curve with smooth cubic curves
                Path { path in
                    guard controlPoints.count >= 2 else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height

                    // Start at first point
                    let start = denormalizePoint(controlPoints[0], width: width, height: height)
                    path.move(to: start)

                    // Draw smooth cubic bezier curves between points
                    for i in 1..<controlPoints.count {
                        let prevPoint = denormalizePoint(controlPoints[i - 1], width: width, height: height)
                        let currentPoint = denormalizePoint(controlPoints[i], width: width, height: height)

                        if i - 1 < curveHandles.count {
                            let outHandle = denormalizePoint(curveHandles[i - 1].outHandle, width: width, height: height)
                            let inHandle = i < curveHandles.count ? denormalizePoint(curveHandles[i].inHandle, width: width, height: height) : currentPoint

                            path.addCurve(to: currentPoint, control1: outHandle, control2: inHandle)
                        } else {
                            path.addLine(to: currentPoint)
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 3)

                // Draw handle lines
                ForEach(0..<controlPoints.count, id: \.self) { index in
                    if index < curveHandles.count {
                        let point = denormalizePoint(controlPoints[index], width: geometry.size.width, height: geometry.size.height)
                        let inHandle = denormalizePoint(curveHandles[index].inHandle, width: geometry.size.width, height: geometry.size.height)
                        let outHandle = denormalizePoint(curveHandles[index].outHandle, width: geometry.size.width, height: geometry.size.height)

                        // In handle line
                        if index > 0 {
                            Path { path in
                                path.move(to: point)
                                path.addLine(to: inHandle)
                            }
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        }

                        // Out handle line
                        if index < controlPoints.count - 1 {
                            Path { path in
                                path.move(to: point)
                                path.addLine(to: outHandle)
                            }
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        }
                    }
                }

                // Draw handle control points (smaller, semi-transparent)
                ForEach(0..<controlPoints.count, id: \.self) { index in
                    if index < curveHandles.count {
                        let inHandle = denormalizePoint(curveHandles[index].inHandle, width: geometry.size.width, height: geometry.size.height)
                        let outHandle = denormalizePoint(curveHandles[index].outHandle, width: geometry.size.width, height: geometry.size.height)

                        // In handle
                        if index > 0 {
                            Circle()
                                .fill(draggingHandleIndex == index && !draggingIsOut ? Color.orange : Color.white)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
                                .position(inHandle)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            draggingHandleIndex = index
                                            draggingIsOut = false
                                            updateHandle(at: index, isOut: false, location: value.location, width: geometry.size.width, height: geometry.size.height)
                                        }
                                        .onEnded { _ in
                                            draggingHandleIndex = nil
                                        }
                                )
                        }

                        // Out handle
                        if index < controlPoints.count - 1 {
                            Circle()
                                .fill(draggingHandleIndex == index && draggingIsOut ? Color.orange : Color.white)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
                                .position(outHandle)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            draggingHandleIndex = index
                                            draggingIsOut = true
                                            updateHandle(at: index, isOut: true, location: value.location, width: geometry.size.width, height: geometry.size.height)
                                        }
                                        .onEnded { _ in
                                            draggingHandleIndex = nil
                                        }
                                )
                        }
                    }
                }

                // Draw main control points (larger, more prominent)
                ForEach(0..<controlPoints.count, id: \.self) { index in
                    let point = denormalizePoint(controlPoints[index], width: geometry.size.width, height: geometry.size.height)

                    Circle()
                        .fill(draggingIndex == index ? Color.blue : Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .position(point)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    draggingIndex = index
                                    updatePoint(at: index, location: value.location, width: geometry.size.width, height: geometry.size.height)
                                }
                                .onEnded { _ in
                                    draggingIndex = nil
                                }
                        )
                }
            }
        }
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            if controlPoints.isEmpty {
                initializeDefaultCurve()
            }
        }
    }

    private func initializeDefaultCurve() {
        // Create 6 points (5 segments) with default ease-in-out curve
        controlPoints = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 0.2, y: 0.4),
            CGPoint(x: 0.4, y: 0.7),
            CGPoint(x: 0.6, y: 0.85),
            CGPoint(x: 0.8, y: 0.95),
            CGPoint(x: 1.0, y: 1.0)
        ]

        // Initialize handles for smooth curves
        curveHandles = controlPoints.map { point in
            // Default handles offset horizontally from the point
            let offset: CGFloat = 0.05
            return (
                inHandle: CGPoint(x: max(0, point.x - offset), y: point.y),
                outHandle: CGPoint(x: min(1, point.x + offset), y: point.y)
            )
        }
    }

    private func denormalizePoint(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return CGPoint(
            x: point.x * width,
            y: (1.0 - point.y) * height  // Invert Y for screen coordinates
        )
    }

    private func normalizePoint(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        return CGPoint(
            x: max(0, min(1, point.x / width)),
            y: max(0, min(1, 1.0 - (point.y / height)))  // Invert Y for screen coordinates
        )
    }

    private func updatePoint(at index: Int, location: CGPoint, width: CGFloat, height: CGFloat) {
        var normalized = normalizePoint(location, width: width, height: height)

        // Lock first and last points to their X positions
        if index == 0 {
            normalized.x = 0.0
        } else if index == controlPoints.count - 1 {
            normalized.x = 1.0
        } else {
            // Constrain X to be between neighboring points
            let prevX = controlPoints[index - 1].x
            let nextX = controlPoints[index + 1].x
            normalized.x = max(prevX + 0.01, min(nextX - 0.01, normalized.x))
        }

        // Update the main point
        let delta = CGPoint(x: normalized.x - controlPoints[index].x, y: normalized.y - controlPoints[index].y)
        controlPoints[index] = normalized

        // Move the handles with the point to maintain curve shape
        if index < curveHandles.count {
            curveHandles[index].inHandle.x += delta.x
            curveHandles[index].inHandle.y += delta.y
            curveHandles[index].outHandle.x += delta.x
            curveHandles[index].outHandle.y += delta.y
        }
    }

    private func updateHandle(at index: Int, isOut: Bool, location: CGPoint, width: CGFloat, height: CGFloat) {
        guard index < curveHandles.count else { return }

        var normalized = normalizePoint(location, width: width, height: height)

        // Clamp to 0-1 range
        normalized.x = max(0, min(1, normalized.x))
        normalized.y = max(0, min(1, normalized.y))

        if isOut {
            curveHandles[index].outHandle = normalized
        } else {
            curveHandles[index].inHandle = normalized
        }
    }
}

#Preview {
    BezierCurveEditorView(controlPoints: .constant([]))
        .frame(height: 300)
        .padding()
}
