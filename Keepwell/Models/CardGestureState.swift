import CoreGraphics

/// Gesture state for the swipe card: swipe to decide at 1x, pinch / double-tap to zoom, pan while zoomed.
/// Pure value type so the rules (a zoomed card never commits a keep or delete) are unit tested.
struct CardGestureState: Equatable, Sendable {
    enum Commit: Equatable, Sendable { case keep, delete }
    /// What the current one-finger drag does. Decided when the drag starts and kept until it ends.
    enum DragMode: Equatable, Sendable { case idle, swipe, pan, blocked }

    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2.5
    /// Above this the card asks for a higher-resolution image.
    static let highResolutionScale: CGFloat = 1.5
    /// A pinch released below this snaps back to 1x.
    static let snapBackScale: CGFloat = 1.05
    static let commitDistance: CGFloat = 110
    static let commitPredictedDistance: CGFloat = 300

    private(set) var scale: CGFloat = 1
    /// Pan of the zoomed image inside the card.
    private(set) var offset: CGSize = .zero
    /// Card translation while swiping at 1x.
    private(set) var swipe: CGSize = .zero
    private(set) var isPinching = false
    private(set) var dragMode: DragMode = .idle
    /// Card size, used to keep the zoomed image covering the card while panning.
    var container: CGSize = .zero

    private var pinchBase: CGFloat = 1
    private var panBase: CGSize = .zero

    var isZoomed: Bool { scale > Self.minScale + 0.01 }
    /// Keep / delete (swipe or buttons) is only possible at 1x with no pinch in progress.
    var canDecide: Bool { !isZoomed && !isPinching }
    var wantsHighResolution: Bool { scale > Self.highResolutionScale }

    // MARK: Pinch

    mutating func pinchChanged(_ magnification: CGFloat) {
        if !isPinching {
            isPinching = true
            pinchBase = scale
            swipe = .zero
            if dragMode == .swipe { dragMode = .blocked }
        }
        scale = Self.clampScale(pinchBase * magnification)
        offset = clampOffset(offset)
    }

    mutating func pinchEnded() {
        isPinching = false
        if scale < Self.snapBackScale { resetZoom() }
        panBase = offset
    }

    // MARK: Drag

    mutating func dragChanged(_ translation: CGSize) {
        if dragMode == .idle {
            dragMode = canDecide ? .swipe : .pan
            panBase = offset
        }
        switch dragMode {
        case .swipe:
            if canDecide { swipe = translation } else { dragMode = .blocked; swipe = .zero }
        case .pan:
            offset = clampOffset(CGSize(width: panBase.width + translation.width,
                                        height: panBase.height + translation.height))
        case .blocked, .idle:
            break
        }
    }

    /// Returns a decision only for a swipe that started and ended at 1x. Otherwise the caller
    /// animates `cancelSwipe()` (no-op when nothing moved).
    mutating func dragEnded(translation: CGSize, predictedEnd: CGSize) -> Commit? {
        let mode = dragMode
        dragMode = .idle
        panBase = offset
        guard mode == .swipe, canDecide else { swipe = .zero; return nil }
        if translation.width > Self.commitDistance || predictedEnd.width > Self.commitPredictedDistance { return .keep }
        if translation.width < -Self.commitDistance || predictedEnd.width < -Self.commitPredictedDistance { return .delete }
        return nil
    }

    mutating func cancelSwipe() { swipe = .zero }

    // MARK: Double tap and reset

    mutating func doubleTap() {
        guard !isPinching else { return }
        if isZoomed { resetZoom() } else { scale = Self.doubleTapScale; offset = .zero; swipe = .zero }
        panBase = offset
    }

    mutating func resetZoom() {
        scale = Self.minScale
        offset = .zero
        panBase = .zero
    }

    /// New card: back to 1x, nothing in flight.
    mutating func reset() {
        let size = container
        self = CardGestureState()
        container = size
    }

    #if DEBUG
    /// Screenshot hook: holds the card mid-swipe.
    mutating func debugHoldSwipe(_ translation: CGSize) { swipe = translation }
    #endif

    // MARK: Math

    static func clampScale(_ s: CGFloat) -> CGFloat {
        guard s.isFinite else { return minScale }
        return min(maxScale, max(minScale, s))
    }

    /// The scaled image may move at most half of its overflow in each direction.
    func clampOffset(_ proposed: CGSize) -> CGSize {
        let maxX = max(0, container.width * (scale - 1) / 2)
        let maxY = max(0, container.height * (scale - 1) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)),
                      height: min(maxY, max(-maxY, proposed.height)))
    }
}
