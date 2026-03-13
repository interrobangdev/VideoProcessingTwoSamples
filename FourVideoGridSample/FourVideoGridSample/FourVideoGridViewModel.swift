//
//  FourVideoGridViewModel.swift
//  FourVideoGridSample
//

import SwiftUI
import Foundation
import AVKit
import VideoProcessingTwo
import QuartzCore
internal import Combine

class FourVideoGridViewModel: NSObject, ObservableObject {
    @Published var displayCIImage: CIImage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPlaying = false
    @Published var isSolving = false

    // Video selection
    @Published var videoURLs: [URL] = []
    @Published var isSelectingAlternateVideos = false
    @Published var isLoadingPickedVideos = false
    var hasVideos: Bool { videoURLs.count == 4 }

    // Scene configuration
    private let sceneSize = CGSize(width: 1080, height: 1080)  // Square for puzzle
    private let frameRate: Double = 30.0

    // Default video filenames from bundle
    private let defaultVideoNames = ["video1", "video2", "video3", "video4"]

    // AVPlayer-based playback
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var videoScene: VideoScene?
    private var sceneDuration: Double = 10.0
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var currentItemObservation: NSKeyValueObservation?

    // Puzzle state
    private(set) var puzzleFilter: SlidingPuzzleFilter?

    // Animation state
    private var isAnimatingTile = false
    private var animationStartTime: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 0.15  // 150ms for faster solving

    // Solver state
    private var solutionMoves: [Int] = []  // Queue of tile indices to move

    override init() {
        super.init()
        loadDefaultVideos()
    }

    private func loadDefaultVideos() {
        videoURLs.removeAll()
        for name in defaultVideoNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                videoURLs.append(url)
            } else if let url = Bundle.main.url(forResource: name, withExtension: "mov") {
                videoURLs.append(url)
            }
        }
        if hasVideos {
            loadComposition()
        }
    }

    func startSelectingAlternateVideos() {
        isSelectingAlternateVideos = true
        // Clear current videos for new selection
        clearVideosForSelection()
    }

    func cancelAlternateSelection() {
        isSelectingAlternateVideos = false
        // Reset to defaults if selection was cancelled
        if !hasVideos {
            loadDefaultVideos()
        }
    }

    func addVideo(url: URL) {
        guard videoURLs.count < 4 else { return }
        videoURLs.append(url)

        // Auto-load when we have 4 videos
        if videoURLs.count == 4 {
            isSelectingAlternateVideos = false
            loadComposition()
        }
    }

    private func clearVideosForSelection() {
        pause()
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        displayCIImage = nil
        videoScene = nil
        puzzleFilter = nil
        player = nil
        playerItem = nil
        videoOutput = nil
        queuePlayer = nil
        playerLooper = nil
        videoURLs.removeAll()
    }

    func resetToDefaultVideos() {
        pause()
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        displayCIImage = nil
        videoScene = nil
        puzzleFilter = nil
        player = nil
        playerItem = nil
        videoOutput = nil
        queuePlayer = nil
        playerLooper = nil
        videoURLs.removeAll()
        isSelectingAlternateVideos = false
        loadDefaultVideos()
    }

    func clearVideos() {
        videoURLs.removeAll()
        pause()
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        displayCIImage = nil
        videoScene = nil
        puzzleFilter = nil
        player = nil
        playerItem = nil
        videoOutput = nil
        queuePlayer = nil
        playerLooper = nil
    }

    func loadComposition() {
        guard hasVideos else {
            errorMessage = "Please select 4 videos"
            return
        }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            self.setupScene(with: self.videoURLs)
        }
    }

    private func setupScene(with videoURLs: [URL]) {
        // Calculate the shortest video duration
        var shortestDuration: Double = .greatestFiniteMagnitude

        for url in videoURLs {
            let asset = AVAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            if duration < shortestDuration {
                shortestDuration = duration
            }
        }

        sceneDuration = min(shortestDuration, 300.0)

        // Create scene using composition mode for proper AVPlayer timing
        let scene = createGridScene(videoURLs: videoURLs, duration: sceneDuration)

        // Create composition from scene
        guard let result = SceneVideoComposition.createComposition(scene: scene) else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create composition"
                self.isLoading = false
            }
            return
        }

        DispatchQueue.main.async {
            self.videoScene = scene
            self.setupPlayer(with: result)
            self.isLoading = false
        }
    }

    private func createGridScene(videoURLs: [URL], duration: Double) -> VideoScene {
        let scene = VideoScene(duration: duration, frameRate: frameRate, size: sceneSize)

        // Grid layout: 2x2 grid for 4 videos
        let cellWidth = sceneSize.width / 2
        let cellHeight = sceneSize.height / 2

        // Grid positions (origin at bottom-left in composition coordinates)
        let gridPositions: [CGRect] = [
            CGRect(x: 0, y: cellHeight, width: cellWidth, height: cellHeight),           // Top-left
            CGRect(x: cellWidth, y: cellHeight, width: cellWidth, height: cellHeight),   // Top-right
            CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight),                    // Bottom-left
            CGRect(x: cellWidth, y: 0, width: cellWidth, height: cellHeight)             // Bottom-right
        ]

        // Add each video to the grid using composition mode for AVPlayer timing
        for (index, url) in videoURLs.enumerated() {
            let videoSource = VideoSource(url: url, useComposition: true)
            videoSource.compositionStartTime = 0.0
            videoSource.duration = duration
            videoSource.sourceStartTime = 0.0

            let surface = Surface(
                source: videoSource,
                frame: gridPositions[index],
                rotation: 0
            )

            let layer = Layer(surfaces: [surface])
            let group = LayerGroup(groups: [], layers: [layer], filters: [], mask: nil)
            scene.group.groups.append(group)
        }

        // Create sliding puzzle filter (applied manually to output frames for interactivity)
        // Don't add to scene - we apply it after getting frames from AVPlayerItemVideoOutput
        let puzzle = SlidingPuzzleFilter()
        puzzle.shuffle(moves: 50)
        self.puzzleFilter = puzzle

        return scene
    }

    private func setupPlayer(with result: SceneCompositionResult) {
        // Setup video output for frame extraction
        let outputSettings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        self.videoOutput = output

        // Create player item with composition
        let item = AVPlayerItem(asset: result.composition)
        item.videoComposition = result.videoComposition
        if let audioMix = result.audioMix {
            item.audioMix = audioMix
        }
        item.add(output)

        self.playerItem = item

        // Use AVQueuePlayer with AVPlayerLooper for seamless looping
        let qPlayer = AVQueuePlayer()
        self.queuePlayer = qPlayer
        self.player = qPlayer

        // Create looper - it manages the queue automatically
        self.playerLooper = AVPlayerLooper(player: qPlayer, templateItem: item)

        // Observe current item changes to add video output
        currentItemObservation = qPlayer.observe(\.currentItem, options: [.new]) { [weak self] player, change in
            guard let self = self,
                  let newItem = change.newValue as? AVPlayerItem,
                  let output = self.videoOutput else { return }

            // Add video output to the new current item if not already present
            if !newItem.outputs.contains(where: { $0 === output }) {
                newItem.add(output)
            }
        }

        play()
    }

    // MARK: - Playback Controls

    func play() {
        guard queuePlayer != nil else { return }
        guard !isPlaying else { return }

        isPlaying = true
        queuePlayer?.play()

        // Create and start display link for frame updates
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    func pause() {
        isPlaying = false
        queuePlayer?.pause()
        displayLink?.invalidate()
        displayLink = nil
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()

        // Update tile animation if in progress
        if isAnimatingTile {
            let animationElapsed = now - animationStartTime
            let progress = min(animationElapsed / animationDuration, 1.0)

            // Ease out cubic for smooth deceleration
            let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
            puzzleFilter?.animationProgress = easedProgress
            puzzleFilter?.updateFilterValue(filterProperty: .intensity, value: easedProgress)

            if progress >= 1.0 {
                // Animation complete
                puzzleFilter?.completeTileAnimation()
                isAnimatingTile = false

                // If solving, execute next move
                if isSolving {
                    executeNextSolutionMove()
                }
            }
        }

        // Get current frame from video output
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard let output = videoOutput,
              let currentItem = queuePlayer?.currentItem else { return }

        let currentTime = currentItem.currentTime()

        // Check if a new frame is available
        if output.hasNewPixelBuffer(forItemTime: currentTime) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                // Convert to CIImage
                var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

                // Apply puzzle filter manually since video composition already rendered the grid
                // The puzzle filter needs to be applied to the composed frame
                if let puzzle = puzzleFilter {
                    if let filtered = puzzle.filterContent(image: ciImage, sourceTime: currentTime, sceneTime: currentTime, compositionTime: currentTime) {
                        ciImage = filtered
                    }
                }

                self.displayCIImage = ciImage
            }
        }
    }

    // MARK: - Puzzle Interaction

    /// Move a tile if possible (with animation)
    func moveTile(at position: Int) {
        guard let puzzle = puzzleFilter else { return }
        guard !isAnimatingTile else { return }  // Don't allow moves during animation
        guard !isSolving else { return }  // Don't allow manual moves while solving

        // Find which tile is at this position
        guard let tileIndex = puzzle.tilePositions.firstIndex(of: position) else { return }

        // Check if this tile can move
        if puzzle.canMoveTile(tileIndex: tileIndex) {
            // Start animation
            puzzle.startTileAnimation(tileIndex: tileIndex)
            isAnimatingTile = true
            animationStartTime = CACurrentMediaTime()
        }
    }

    /// Shuffle the puzzle
    func shufflePuzzle() {
        guard !isAnimatingTile else { return }
        guard !isSolving else { return }
        puzzleFilter?.shuffle(moves: 50)
    }

    /// Grid size from the puzzle filter
    var gridSize: Int {
        puzzleFilter?.gridSize ?? 3
    }

    /// Check if puzzle is solved
    var isPuzzleSolved: Bool {
        guard let puzzle = puzzleFilter else { return false }
        // Solved when each tile i is at position i (except empty tile)
        for i in 0..<puzzle.totalTiles {
            if i != puzzle.emptyTileIndex && puzzle.tilePositions[i] != i {
                return false
            }
        }
        return true
    }

    // MARK: - Puzzle Solver

    @Published var isFindingSolution = false

    /// Start solving the puzzle automatically
    func solvePuzzle() {
        guard !isSolving else { return }
        guard !isFindingSolution else { return }
        guard !isAnimatingTile else { return }
        guard let puzzle = puzzleFilter else { return }

        // Run solver on background thread for large puzzles
        isFindingSolution = true
        let positions = puzzle.tilePositions
        let emptyIdx = puzzle.emptyTileIndex

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let solution = self?.findSolution(from: positions, emptyIndex: emptyIdx)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFindingSolution = false

                if let solution = solution, !solution.isEmpty {
                    self.solutionMoves = solution
                    self.isSolving = true
                    self.executeNextSolutionMove()
                } else if solution?.isEmpty == true {
                    // Already solved
                } else {
                    // No solution found - show error briefly
                    self.errorMessage = "Could not find solution (puzzle may be too complex)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.errorMessage == "Could not find solution (puzzle may be too complex)" {
                            self.errorMessage = nil
                        }
                    }
                }
            }
        }
    }

    /// Stop solving
    func stopSolving() {
        isSolving = false
        solutionMoves.removeAll()
    }

    private func executeNextSolutionMove() {
        guard isSolving else { return }
        guard let puzzle = puzzleFilter else { return }

        if solutionMoves.isEmpty {
            // Done solving
            isSolving = false
            return
        }

        let tileIndex = solutionMoves.removeFirst()

        // Verify the move is still valid
        if puzzle.canMoveTile(tileIndex: tileIndex) {
            puzzle.startTileAnimation(tileIndex: tileIndex)
            isAnimatingTile = true
            animationStartTime = CACurrentMediaTime()
        } else {
            // Move no longer valid, stop solving
            isSolving = false
            solutionMoves.removeAll()
        }
    }

    /// A* solver for sliding puzzle using Manhattan distance heuristic
    /// Returns array of tile indices to move, in order
    private func findSolution(from initialPositions: [Int], emptyIndex: Int) -> [Int]? {
        guard let puzzle = puzzleFilter else { return nil }
        let gridSize = puzzle.gridSize
        let totalTiles = puzzle.totalTiles

        // Goal state: tile i at position i
        let goalPositions = Array(0..<totalTiles)

        // Check if already solved
        if initialPositions == goalPositions {
            return []
        }

        // Calculate Manhattan distance heuristic
        func manhattanDistance(_ positions: [Int], emptyIdx: Int) -> Int {
            var distance = 0
            for tileIndex in 0..<totalTiles {
                if tileIndex == emptyIdx { continue }
                let currentPos = positions[tileIndex]
                let goalPos = tileIndex  // Goal: tile i at position i

                let currentRow = currentPos / gridSize
                let currentCol = currentPos % gridSize
                let goalRow = goalPos / gridSize
                let goalCol = goalPos % gridSize

                distance += abs(currentRow - goalRow) + abs(currentCol - goalCol)
            }
            return distance
        }

        // State for A*
        struct State: Hashable {
            let positions: [Int]
            let emptyIndex: Int
        }

        struct Node: Comparable {
            let state: State
            let moves: [Int]
            let gCost: Int      // Cost to reach this node
            let fCost: Int      // gCost + heuristic

            static func < (lhs: Node, rhs: Node) -> Bool {
                if lhs.fCost != rhs.fCost {
                    return lhs.fCost < rhs.fCost
                }
                return lhs.gCost > rhs.gCost  // Prefer deeper nodes when f is equal
            }
        }

        // Get neighbors of a position
        func getNeighborPositions(of position: Int) -> [Int] {
            var neighbors: [Int] = []
            let row = position / gridSize
            let col = position % gridSize

            if row > 0 { neighbors.append(position - gridSize) }
            if row < gridSize - 1 { neighbors.append(position + gridSize) }
            if col > 0 { neighbors.append(position - 1) }
            if col < gridSize - 1 { neighbors.append(position + 1) }

            return neighbors
        }

        let initialState = State(positions: initialPositions, emptyIndex: emptyIndex)
        let initialH = manhattanDistance(initialPositions, emptyIdx: emptyIndex)

        var visited = Set<State>()
        var openSet = [Node(state: initialState, moves: [], gCost: 0, fCost: initialH)]

        // Max iterations to prevent infinite loops
        let maxIterations = 2_000_000
        var iterations = 0

        while !openSet.isEmpty && iterations < maxIterations {
            iterations += 1

            // Find node with lowest fCost (simple linear search - could use heap for better perf)
            var bestIndex = 0
            for i in 1..<openSet.count {
                if openSet[i] < openSet[bestIndex] {
                    bestIndex = i
                }
            }
            let node = openSet.remove(at: bestIndex)

            let currentPositions = node.state.positions
            let currentEmptyIndex = node.state.emptyIndex

            // Check if solved
            if currentPositions == goalPositions {
                return node.moves
            }

            if visited.contains(node.state) {
                continue
            }
            visited.insert(node.state)

            let emptyPosition = currentPositions[currentEmptyIndex]
            let neighborPositions = getNeighborPositions(of: emptyPosition)

            for neighborPos in neighborPositions {
                guard let tileIndex = currentPositions.firstIndex(of: neighborPos) else { continue }

                var newPositions = currentPositions
                newPositions[tileIndex] = emptyPosition
                newPositions[currentEmptyIndex] = neighborPos

                let newState = State(positions: newPositions, emptyIndex: currentEmptyIndex)

                if visited.contains(newState) {
                    continue
                }

                let newG = node.gCost + 1
                let newH = manhattanDistance(newPositions, emptyIdx: currentEmptyIndex)
                let newF = newG + newH

                let newMoves = node.moves + [tileIndex]
                openSet.append(Node(state: newState, moves: newMoves, gCost: newG, fCost: newF))
            }
        }

        // No solution found
        return nil
    }

    deinit {
        displayLink?.invalidate()
        currentItemObservation?.invalidate()
    }
}
