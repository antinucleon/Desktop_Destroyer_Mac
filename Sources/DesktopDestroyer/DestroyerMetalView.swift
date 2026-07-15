import AppKit
import MetalKit
import simd

final class DestroyerMetalView: MTKView {
    private(set) var renderer: DestroyerRenderer!
    var onToolShortcut: ((DestructionTool) -> Void)?
    var onResetShortcut: (() -> Void)?
    var onCaptureShortcut: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
    private let soundController = ToolSoundController()
    private lazy var invisibleCursor = NSCursor(image: NSImage(size: NSSize(width: 2, height: 2)), hotSpot: .zero)

    init(frame: CGRect, device: MTLDevice) throws {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColor(red: 0.018, green: 0.022, blue: 0.032, alpha: 1)
        preferredFramesPerSecond = 120
        enableSetNeedsDisplay = false
        isPaused = false
        framebufferOnly = true
        autoResizeDrawable = true
        wantsLayer = true
        renderer = try DestroyerRenderer(view: self)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: invisibleCursor)
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        renderer.pointerHovered(at: metalPoint(for: event))
    }

    override func mouseEntered(with event: NSEvent) {
        renderer.pointerHovered(at: metalPoint(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        renderer.pointerExited()
    }

    override func cursorUpdate(with event: NSEvent) {
        invisibleCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        soundController.begin(renderer.selectedTool)
        renderer.pointerBegan(at: metalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        renderer.pointerMoved(to: metalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        soundController.end()
        renderer.pointerEnded(at: metalPoint(for: event))
    }

    func stopAllSounds() {
        soundController.stopAll()
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }
        if let number = Int(characters), (1...9).contains(number),
           let tool = DestructionTool(rawValue: UInt32(number - 1)) {
            onToolShortcut?(tool)
        } else if characters == "r" {
            onResetShortcut?()
        } else if characters == "c" {
            onCaptureShortcut?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func metalPoint(for event: NSEvent) -> SIMD2<Float> {
        let local = convert(event.locationInWindow, from: nil)
        let xScale = drawableSize.width / max(bounds.width, 1)
        let yScale = drawableSize.height / max(bounds.height, 1)
        return SIMD2(Float(local.x * xScale), Float(local.y * yScale))
    }
}
