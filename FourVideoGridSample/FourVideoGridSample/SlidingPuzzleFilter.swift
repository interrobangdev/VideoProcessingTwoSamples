//
//  SlidingPuzzleFilter.swift
//  FourVideoGridSample
//
//  A filter that divides the image into a 3x3 grid for a sliding puzzle game
//

import CoreMedia
import CoreImage
import VideoProcessingTwo

class SlidingPuzzleFilter: Filter {
    var filterAnimators: [FilterAnimator]

    /// Grid size (3 = 3x3 grid, 4 = 4x4 grid, etc.)
    /// Change this single value to adjust the puzzle size
    let gridSize: Int = 5

    /// Total number of tiles (gridSize * gridSize)
    var totalTiles: Int { gridSize * gridSize }

    /// Maps tile index to grid position
    /// Position 0 = top-left, increases left-to-right, top-to-bottom
    var tilePositions: [Int]

    /// Which tile index is currently hidden (the empty space)
    var emptyTileIndex: Int

    /// Animated offset for a tile that's currently sliding
    /// Key is tile index, value is (dx, dy) offset in grid units
    var tileAnimationOffsets: [Int: CGPoint]

    /// Which tile is currently animating
    var animatingTileIndex: Int?

    /// Animation progress (0.0 to 1.0)
    var animationProgress: Double = 0.0

    /// Target position for the animating tile
    var animationTargetPosition: Int?

    init(filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators

        // Initial solved state: tile i is at position i
        let total = gridSize * gridSize
        self.tilePositions = Array(0..<total)
        self.emptyTileIndex = total - 1  // Bottom-right is empty by default
        self.tileAnimationOffsets = [:]
    }

    /// Shuffle the puzzle
    func shuffle(moves: Int = 100) {
        for _ in 0..<moves {
            let neighbors = getNeighborPositions(of: tilePositions[emptyTileIndex])
            if let randomNeighbor = neighbors.randomElement(),
               let tileAtNeighbor = tilePositions.firstIndex(of: randomNeighbor) {
                swapTileWithEmpty(tileIndex: tileAtNeighbor)
            }
        }
    }

    /// Get positions adjacent to a given position
    private func getNeighborPositions(of position: Int) -> [Int] {
        var neighbors: [Int] = []
        let row = position / gridSize
        let col = position % gridSize

        if row > 0 { neighbors.append(position - gridSize) }  // Above
        if row < gridSize - 1 { neighbors.append(position + gridSize) }  // Below
        if col > 0 { neighbors.append(position - 1) }  // Left
        if col < gridSize - 1 { neighbors.append(position + 1) }  // Right

        return neighbors
    }

    /// Check if a tile can move (is adjacent to empty space)
    func canMoveTile(tileIndex: Int) -> Bool {
        let tilePosition = tilePositions[tileIndex]
        let emptyPosition = tilePositions[emptyTileIndex]
        return getNeighborPositions(of: emptyPosition).contains(tilePosition)
    }

    /// Swap a tile with the empty space (instant, no animation)
    func swapTileWithEmpty(tileIndex: Int) {
        guard canMoveTile(tileIndex: tileIndex) else { return }
        let tilePos = tilePositions[tileIndex]
        let emptyPos = tilePositions[emptyTileIndex]
        tilePositions[tileIndex] = emptyPos
        tilePositions[emptyTileIndex] = tilePos
    }

    /// Start animating a tile move
    func startTileAnimation(tileIndex: Int) {
        guard canMoveTile(tileIndex: tileIndex) else { return }
        animatingTileIndex = tileIndex
        animationTargetPosition = tilePositions[emptyTileIndex]
        animationProgress = 0.0
    }

    /// Complete the animation and swap positions
    func completeTileAnimation() {
        if let tileIndex = animatingTileIndex {
            swapTileWithEmpty(tileIndex: tileIndex)
        }
        animatingTileIndex = nil
        animationTargetPosition = nil
        animationProgress = 0.0
        tileAnimationOffsets.removeAll()
    }

    func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .intensity,
           let val = value as? Double {
            self.animationProgress = val
            updateAnimationOffset()
        }
    }

    private func updateAnimationOffset() {
        guard let tileIndex = animatingTileIndex,
              let targetPos = animationTargetPosition else {
            return
        }

        let currentPos = tilePositions[tileIndex]
        let currentRow = currentPos / gridSize
        let currentCol = currentPos % gridSize
        let targetRow = targetPos / gridSize
        let targetCol = targetPos % gridSize

        let dx = Double(targetCol - currentCol) * animationProgress
        let dy = Double(targetRow - currentRow) * animationProgress

        tileAnimationOffsets[tileIndex] = CGPoint(x: dx, y: dy)
    }

    func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        let extent = image.extent
        let tileWidth = extent.width / CGFloat(gridSize)
        let tileHeight = extent.height / CGFloat(gridSize)

        var outputImage: CIImage? = nil

        // Render each tile
        for tileIndex in 0..<(gridSize * gridSize) {
            // Skip the empty tile
            if tileIndex == emptyTileIndex {
                continue
            }

            // Get current position for this tile
            let position = tilePositions[tileIndex]

            // Calculate source crop region (where this tile's image comes from)
            // Tile index determines which part of the original image
            let sourceRow = tileIndex / gridSize
            let sourceCol = tileIndex % gridSize
            let sourceRect = CGRect(
                x: extent.minX + CGFloat(sourceCol) * tileWidth,
                y: extent.minY + CGFloat(sourceRow) * tileHeight,
                width: tileWidth,
                height: tileHeight
            )

            // Crop the tile from source
            let croppedTile = image.cropped(to: sourceRect)

            // Calculate destination position
            let destRow = position / gridSize
            let destCol = position % gridSize

            // Apply animation offset if this tile is animating
            var offsetX: CGFloat = 0
            var offsetY: CGFloat = 0
            if let offset = tileAnimationOffsets[tileIndex] {
                offsetX = CGFloat(offset.x) * tileWidth
                offsetY = CGFloat(offset.y) * tileHeight
            }

            // Calculate translation from source position to destination position
            let sourceX = extent.minX + CGFloat(sourceCol) * tileWidth
            let sourceY = extent.minY + CGFloat(sourceRow) * tileHeight
            let destX = extent.minX + CGFloat(destCol) * tileWidth + offsetX
            let destY = extent.minY + CGFloat(destRow) * tileHeight + offsetY

            let translateX = destX - sourceX
            let translateY = destY - sourceY

            let translatedTile = croppedTile.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))

            // Composite onto output
            if let existingOutput = outputImage {
                outputImage = translatedTile.composited(over: existingOutput)
            } else {
                outputImage = translatedTile
            }
        }

        return outputImage
    }
}
