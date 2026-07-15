import AppKit
import CoreGraphics
import MetalKit
import QuartzCore
import simd

private struct StampUniforms {
    var origin: SIMD2<UInt32>
    var textureSize: SIMD2<UInt32>
    var center: SIMD2<Float>
    var radius: Float
    var hardness: Float
    var color: SIMD4<Float>
    var kind: UInt32
    var seed: Float
    var rotation: Float
    var assetMix: Float
}

private struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var life: Float
    var maxLife: Float
    var size: Float
    var kind: UInt32
}

private struct ParticleUpdateUniforms {
    var deltaTime: Float
    var padding: Float = 0
    var viewport: SIMD2<Float>
}

private struct ParticleRenderUniforms {
    var viewport: SIMD2<Float>
    var time: Float
    var padding: Float = 0
}

private struct CompositeUniforms {
    var viewport: SIMD2<Float>
    var backgroundSize: SIMD2<Float>
    var time: Float
    var damageEnergy: Float
    var padding: SIMD2<Float> = .zero
}

private struct CursorUniforms {
    var position: SIMD2<Float>
    var viewport: SIMD2<Float>
    var size: SIMD2<Float>
    var anchor: SIMD2<Float>
    var cell: UInt32
    var opacity: Float
    var rotation: Float
    var brightness: Float
}

private struct ContactEffect {
    var position: SIMD2<Float>
    var direction: SIMD2<Float>
    var color: SIMD4<Float>
    var age: Float
    var lifetime: Float
    var size: Float
    var rotation: Float
    var kind: UInt32
    var seed: Float
    var padding: SIMD2<Float> = .zero
}

private struct DamageStamp {
    var point: SIMD2<Float>
    var radius: Float
    var hardness: Float
    var color: SIMD4<Float>
    var kind: UInt32
    var seed: Float
    var rotation: Float
    var assetMix: Float
}

private struct ParticleSpawn {
    var point: SIMD2<Float>
    var count: Int
    var color: SIMD4<Float>
    var minimumSpeed: Float
    var maximumSpeed: Float
    var upwardBias: Float
    var kind: UInt32
    var lifetime: ClosedRange<Float>
    var size: ClosedRange<Float>
    var direction: SIMD2<Float>
    var spread: Float
}

private struct Termite {
    var position: SIMD2<Float>
    var heading: Float
    var speed: Float
    var life: Float
    var chewCooldown: Float
}

struct RenderStats {
    var framesPerSecond: Int
    var marks: Int
    var termites: Int
}

enum RendererError: LocalizedError {
    case noCommandQueue
    case shaderFunction(String)
    case particleBuffer

    var errorDescription: String? {
        switch self {
        case .noCommandQueue: "Metal could not create a command queue."
        case .shaderFunction(let name): "Metal shader function \(name) is missing."
        case .particleBuffer: "Metal could not allocate the particle buffers."
        }
    }
}

final class DestroyerRenderer: NSObject, MTKViewDelegate {
    static let maximumParticles = 8_192
    static let maximumTermites = 256
    static let maximumContactEffects = 512

    var onStats: ((RenderStats) -> Void)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let stampPipeline: MTLComputePipelineState
    private let clearPipeline: MTLComputePipelineState
    private let particleUpdatePipeline: MTLComputePipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let particlePipeline: MTLRenderPipelineState
    private let contactEffectPipeline: MTLRenderPipelineState
    private let cursorPipeline: MTLRenderPipelineState
    private let particleBuffer: MTLBuffer
    private let termiteBuffer: MTLBuffer
    private let contactEffectBuffer: MTLBuffer
    private let toolCursorTexture: MTLTexture
    private let paintCursorTexture: MTLTexture
    private let termiteCursorTexture: MTLTexture
    private let damageDecalTexture: MTLTexture
    private let particleAtlasTexture: MTLTexture
    private let termiteAtlasTexture: MTLTexture
    private let stampAtlasTexture: MTLTexture
    private let inFlightSemaphore = DispatchSemaphore(value: 1)

    private weak var view: MTKView?
    private var backgroundTexture: MTLTexture
    private var backgroundSize = SIMD2<Float>(1, 1)
    private var damageTexture: MTLTexture?
    private var damageTextureSize = SIMD2<UInt32>(0, 0)
    private var pendingStamps: [DamageStamp] = []
    private var pendingSpawns: [ParticleSpawn] = []
    private var contactEffects: [ContactEffect] = []
    private var termites: [Termite] = []
    private var particleCursor = 0
    private var shouldClear = true
    private var shouldResetParticles = false
    private var marks = 0
    private var pointerIsDown = false
    private var pointerPoint = SIMD2<Float>.zero
    private var pointerIsVisible = false
    private var lastPointerPoint = SIMD2<Float>.zero
    private var lastContinuousEmission = CACurrentMediaTime()
    private(set) var selectedTool: DestructionTool = .hammer
    private var lastActivationTime = CACurrentMediaTime() - 10
    private var lastFrameTime = CACurrentMediaTime()
    private var statsStartTime = CACurrentMediaTime()
    private var framesSinceStats = 0

    init(view: MTKView) throws {
        guard let metalDevice = view.device,
              let queue = metalDevice.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }
        device = metalDevice
        commandQueue = queue

        let library = try metalDevice.makeLibrary(source: metalShaderSource, options: nil)
        func function(_ name: String) throws -> MTLFunction {
            guard let value = library.makeFunction(name: name) else {
                throw RendererError.shaderFunction(name)
            }
            return value
        }

        stampPipeline = try metalDevice.makeComputePipelineState(function: function("applyStamp"))
        clearPipeline = try metalDevice.makeComputePipelineState(function: function("clearDamage"))
        particleUpdatePipeline = try metalDevice.makeComputePipelineState(function: function("updateParticles"))

        let compositeDescriptor = MTLRenderPipelineDescriptor()
        compositeDescriptor.label = "Desktop composite"
        compositeDescriptor.vertexFunction = try function("fullscreenVertex")
        compositeDescriptor.fragmentFunction = try function("compositeFragment")
        compositeDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        compositePipeline = try metalDevice.makeRenderPipelineState(descriptor: compositeDescriptor)

        let particleDescriptor = MTLRenderPipelineDescriptor()
        particleDescriptor.label = "GPU particles"
        particleDescriptor.vertexFunction = try function("particleVertex")
        particleDescriptor.fragmentFunction = try function("particleFragment")
        let particleColor = particleDescriptor.colorAttachments[0]!
        particleColor.pixelFormat = view.colorPixelFormat
        particleColor.isBlendingEnabled = true
        particleColor.rgbBlendOperation = .add
        particleColor.alphaBlendOperation = .add
        particleColor.sourceRGBBlendFactor = .sourceAlpha
        particleColor.sourceAlphaBlendFactor = .sourceAlpha
        particleColor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleColor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        particlePipeline = try metalDevice.makeRenderPipelineState(descriptor: particleDescriptor)

        let contactDescriptor = MTLRenderPipelineDescriptor()
        contactDescriptor.label = "Animated contact effects"
        contactDescriptor.vertexFunction = try function("contactEffectVertex")
        contactDescriptor.fragmentFunction = try function("contactEffectFragment")
        let contactColor = contactDescriptor.colorAttachments[0]!
        contactColor.pixelFormat = view.colorPixelFormat
        contactColor.isBlendingEnabled = true
        contactColor.rgbBlendOperation = .add
        contactColor.alphaBlendOperation = .add
        contactColor.sourceRGBBlendFactor = .sourceAlpha
        contactColor.sourceAlphaBlendFactor = .sourceAlpha
        contactColor.destinationRGBBlendFactor = .one
        contactColor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        contactEffectPipeline = try metalDevice.makeRenderPipelineState(descriptor: contactDescriptor)

        let cursorDescriptor = MTLRenderPipelineDescriptor()
        cursorDescriptor.label = "Held tool cursor"
        cursorDescriptor.vertexFunction = try function("cursorVertex")
        cursorDescriptor.fragmentFunction = try function("cursorFragment")
        let cursorColor = cursorDescriptor.colorAttachments[0]!
        cursorColor.pixelFormat = view.colorPixelFormat
        cursorColor.isBlendingEnabled = true
        cursorColor.sourceRGBBlendFactor = .sourceAlpha
        cursorColor.sourceAlphaBlendFactor = .sourceAlpha
        cursorColor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        cursorColor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        cursorPipeline = try metalDevice.makeRenderPipelineState(descriptor: cursorDescriptor)

        let particleLength = MemoryLayout<Particle>.stride * Self.maximumParticles
        let termiteLength = MemoryLayout<Particle>.stride * Self.maximumTermites
        let contactLength = MemoryLayout<ContactEffect>.stride * Self.maximumContactEffects
        guard let allocatedParticles = metalDevice.makeBuffer(length: particleLength, options: .storageModeShared),
              let allocatedTermites = metalDevice.makeBuffer(length: termiteLength, options: .storageModeShared),
              let allocatedContacts = metalDevice.makeBuffer(length: contactLength, options: .storageModeShared) else {
            throw RendererError.particleBuffer
        }
        particleBuffer = allocatedParticles
        termiteBuffer = allocatedTermites
        contactEffectBuffer = allocatedContacts
        particleBuffer.label = "Particle simulation"
        termiteBuffer.label = "Termite instances"
        contactEffectBuffer.label = "Animated contact effects"
        memset(particleBuffer.contents(), 0, particleLength)
        memset(termiteBuffer.contents(), 0, termiteLength)
        memset(contactEffectBuffer.contents(), 0, contactLength)

        let transparentTexture = Self.makeTransparentTexture(device: metalDevice)
        toolCursorTexture = Self.loadAssetTexture(named: "tool-cursors.png", device: metalDevice) ?? transparentTexture
        paintCursorTexture = Self.loadAssetTexture(named: "cursor-paint-v2.png", device: metalDevice) ?? transparentTexture
        termiteCursorTexture = Self.loadAssetTexture(named: "cursor-termite-v2.png", device: metalDevice) ?? transparentTexture
        damageDecalTexture = Self.loadAssetTexture(named: "damage-decals-v2.png", device: metalDevice) ?? transparentTexture
        particleAtlasTexture = Self.loadAssetTexture(named: "particle-atlas.png", device: metalDevice) ?? transparentTexture
        termiteAtlasTexture = Self.loadAssetTexture(named: "termite-atlas-v2.png", device: metalDevice) ?? transparentTexture
        stampAtlasTexture = Self.loadAssetTexture(named: "stamp-atlas.png", device: metalDevice) ?? transparentTexture

        backgroundTexture = try Self.makeFallbackTexture(device: metalDevice)
        backgroundSize = SIMD2(Float(backgroundTexture.width), Float(backgroundTexture.height))

        super.init()
        self.view = view
        view.delegate = self
    }

    func select(_ tool: DestructionTool) {
        selectedTool = tool
    }

    func clear() {
        shouldClear = true
        pendingStamps.removeAll(keepingCapacity: true)
        pendingSpawns.removeAll(keepingCapacity: true)
        contactEffects.removeAll(keepingCapacity: true)
        termites.removeAll(keepingCapacity: true)
        shouldResetParticles = true
        marks = 0
    }

    func setBackground(_ image: CGImage) throws {
        let loader = MTKTextureLoader(device: device)
        backgroundTexture = try loader.newTexture(
            cgImage: image,
            options: [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft
            ]
        )
        backgroundTexture.label = "Captured desktop"
        backgroundSize = SIMD2(Float(backgroundTexture.width), Float(backgroundTexture.height))
        clear()
    }

    func pointerBegan(at point: SIMD2<Float>) {
        pointerIsDown = true
        pointerIsVisible = true
        pointerPoint = point
        lastPointerPoint = point
        lastContinuousEmission = 0
        lastActivationTime = CACurrentMediaTime()
        trigger(tool: selectedTool, at: point, direction: .zero)
    }

    func pointerMoved(to point: SIMD2<Float>) {
        guard pointerIsDown else { return }
        let delta = point - lastPointerPoint
        let distance = simd_length(delta)
        pointerPoint = point
        let spacing: Float
        switch selectedTool {
        case .chainsaw: spacing = 13
        case .machineGun: spacing = 24
        case .flameThrower: spacing = 18
        case .colorThrower: spacing = 28
        case .phaser: spacing = 16
        case .washing: spacing = 18
        default: spacing = 34
        }
        if distance >= spacing {
            let steps = min(24, max(1, Int(distance / spacing)))
            for index in 1...steps {
                let fraction = Float(index) / Float(steps)
                trigger(tool: selectedTool, at: simd_mix(lastPointerPoint, point, SIMD2(repeating: fraction)), direction: delta)
            }
            lastPointerPoint = point
        }
    }

    func pointerEnded(at point: SIMD2<Float>) {
        pointerPoint = point
        pointerIsDown = false
    }

    func pointerHovered(at point: SIMD2<Float>) {
        pointerPoint = point
        pointerIsVisible = true
    }

    func pointerExited() {
        pointerIsVisible = false
    }

    func drawableSizeWillChange(_ size: CGSize) {
        damageTextureSize = .zero
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSizeWillChange(size)
    }

    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            inFlightSemaphore.signal()
            return
        }
        commandBuffer.label = "Desktop Destroyer frame"
        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        let now = CACurrentMediaTime()
        let deltaTime = Float(min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 20.0))
        lastFrameTime = now
        let viewport = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        ensureDamageTexture(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))
        guard let damageTexture else {
            commandBuffer.commit()
            return
        }

        emitContinuousToolIfNeeded(now: now)
        updateTermites(deltaTime: deltaTime, viewport: viewport)
        updateContactEffects(deltaTime: deltaTime)
        if shouldResetParticles {
            memset(particleBuffer.contents(), 0, particleBuffer.length)
            shouldResetParticles = false
        }
        writePendingParticles()
        writeTermiteInstances()
        writeContactEffects()

        if shouldClear {
            encodeClear(texture: damageTexture, commandBuffer: commandBuffer)
            shouldClear = false
        }
        encodeStamps(texture: damageTexture, commandBuffer: commandBuffer)
        encodeParticleUpdate(deltaTime: deltaTime, viewport: viewport, commandBuffer: commandBuffer)

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.018, green: 0.022, blue: 0.032, alpha: 1)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.label = "Composite and effects"
            var composite = CompositeUniforms(
                viewport: viewport,
                backgroundSize: backgroundSize,
                time: Float(now.truncatingRemainder(dividingBy: 10_000)),
                damageEnergy: min(1, Float(marks) / 80)
            )
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(backgroundTexture, index: 0)
            encoder.setFragmentTexture(damageTexture, index: 1)
            encoder.setFragmentBytes(&composite, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            var particleUniforms = ParticleRenderUniforms(
                viewport: viewport,
                time: Float(now.truncatingRemainder(dividingBy: 10_000))
            )
            encoder.setRenderPipelineState(particlePipeline)
            encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&particleUniforms, length: MemoryLayout<ParticleRenderUniforms>.stride, index: 1)
            encoder.setFragmentTexture(particleAtlasTexture, index: 0)
            encoder.setFragmentTexture(termiteAtlasTexture, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Self.maximumParticles)

            if !termites.isEmpty {
                encoder.setVertexBuffer(termiteBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: termites.count)
            }

            if !contactEffects.isEmpty {
                encoder.setRenderPipelineState(contactEffectPipeline)
                encoder.setVertexBuffer(contactEffectBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&particleUniforms, length: MemoryLayout<ParticleRenderUniforms>.stride, index: 1)
                encoder.drawPrimitives(
                    type: .triangle,
                    vertexStart: 0,
                    vertexCount: 6,
                    instanceCount: contactEffects.count
                )
            }

            if pointerIsVisible || pointerPoint != .zero {
                let pose = cursorPose(now: now, viewport: viewport)
                let standaloneCursor = selectedTool.standaloneCursorAssetName != nil
                var cursor = CursorUniforms(
                    position: pose.position,
                    viewport: viewport,
                    size: SIMD2(repeating: pose.size),
                    anchor: selectedTool.cursorActionAnchor,
                    cell: standaloneCursor ? 9 : selectedTool.rawValue,
                    opacity: pointerIsDown ? 1 : 0.90,
                    rotation: pose.rotation,
                    brightness: pose.brightness
                )
                encoder.setRenderPipelineState(cursorPipeline)
                encoder.setVertexBytes(&cursor, length: MemoryLayout<CursorUniforms>.stride, index: 0)
                switch selectedTool {
                case .colorThrower:
                    encoder.setFragmentTexture(paintCursorTexture, index: 0)
                case .termites:
                    encoder.setFragmentTexture(termiteCursorTexture, index: 0)
                default:
                    encoder.setFragmentTexture(toolCursorTexture, index: 0)
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        publishStats(now: now)
    }

    private func ensureDamageTexture(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let requested = SIMD2(UInt32(width), UInt32(height))
        guard damageTexture == nil || requested != damageTextureSize else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        damageTexture = device.makeTexture(descriptor: descriptor)
        damageTexture?.label = "Persistent destruction surface"
        damageTextureSize = requested
        shouldClear = true
        marks = 0
    }

    private func encodeClear(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Reset destruction surface"
        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(texture, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(
            MTLSize(width: texture.width, height: texture.height, depth: 1),
            threadsPerThreadgroup: group
        )
        encoder.endEncoding()
    }

    private func encodeStamps(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard !pendingStamps.isEmpty,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Procedural damage stamps"
        encoder.setComputePipelineState(stampPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(damageDecalTexture, index: 1)
        encoder.setTexture(stampAtlasTexture, index: 2)
        let group = MTLSize(width: 16, height: 16, depth: 1)

        for stamp in pendingStamps.prefix(384) {
            let expansion = stamp.radius * 1.25
            let originX = max(0, Int(floor(stamp.point.x - expansion)))
            let originY = max(0, Int(floor(stamp.point.y - expansion)))
            let endX = min(texture.width, Int(ceil(stamp.point.x + expansion)))
            let endY = min(texture.height, Int(ceil(stamp.point.y + expansion)))
            guard endX > originX, endY > originY else { continue }

            var uniforms = StampUniforms(
                origin: SIMD2(UInt32(originX), UInt32(originY)),
                textureSize: SIMD2(UInt32(texture.width), UInt32(texture.height)),
                center: stamp.point,
                radius: stamp.radius,
                hardness: stamp.hardness,
                color: stamp.color,
                kind: stamp.kind,
                seed: stamp.seed,
                rotation: stamp.rotation,
                assetMix: stamp.assetMix
            )
            encoder.setBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: endX - originX, height: endY - originY, depth: 1),
                threadsPerThreadgroup: group
            )
        }
        encoder.endEncoding()
        if pendingStamps.count > 384 {
            pendingStamps.removeFirst(384)
        } else {
            pendingStamps.removeAll(keepingCapacity: true)
        }
    }

    private func encodeParticleUpdate(deltaTime: Float, viewport: SIMD2<Float>, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "GPU particle simulation"
        var uniforms = ParticleUpdateUniforms(deltaTime: deltaTime, viewport: viewport)
        encoder.setComputePipelineState(particleUpdatePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUpdateUniforms>.stride, index: 1)
        let width = min(particleUpdatePipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(
            MTLSize(width: Self.maximumParticles, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }

    private func trigger(tool: DestructionTool, at point: SIMD2<Float>, direction: SIMD2<Float>) {
        lastActivationTime = CACurrentMediaTime()
        let hasDirection = simd_length_squared(direction) > 0.01
        let travelDirection = hasDirection ? simd_normalize(direction) : tool.emissionDirection
        let angle = hasDirection ? atan2(direction.y, direction.x) : 0
        switch tool {
        case .hammer:
            addStamp(point, radius: 230, hardness: 1, color: SIMD4(0.10, 0.10, 0.12, 1), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 92, color: SIMD4(0.94, 0.72, 0.52, 1), speeds: 100...520, upward: 100, kind: 0, life: 0.35...1.1, size: 4...11)
            addContactEffect(point, tool: tool, direction: .zero, color: SIMD4(1.0, 0.78, 0.38, 1), lifetime: 0.34, size: 150, rotation: angle)
            addContactEffect(point, tool: tool, direction: .zero, color: SIMD4(1.0, 0.48, 0.18, 0.72), lifetime: 0.50, size: 235, rotation: angle)
            addContactEffect(point, tool: tool, direction: .zero, color: SIMD4(1.0, 0.30, 0.10, 0.46), lifetime: 0.68, size: 330, rotation: angle)
        case .chainsaw:
            addStamp(point, radius: 72, hardness: 0.96, color: SIMD4(0.14, 0.075, 0.025, 1), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 11, color: SIMD4(1.0, 0.74, 0.42, 1), speeds: 100...340, upward: 20, kind: 7, life: 0.18...0.58, size: 4...11, direction: travelDirection, spread: 2.2)
            addContactEffect(point, tool: tool, direction: travelDirection, color: SIMD4(1.0, 0.52, 0.12, 1), lifetime: 0.22, size: 82, rotation: angle)
        case .machineGun:
            let jitter = SIMD2(Float.random(in: -4...4), Float.random(in: -4...4))
            addStamp(point + jitter, radius: 46, hardness: 1, color: SIMD4(0.16, 0.15, 0.14, 1), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 10, color: SIMD4(1.0, 0.72, 0.26, 1), speeds: 80...330, upward: 30, kind: 1, life: 0.12...0.42, size: 4...10)
            addContactEffect(point, tool: tool, direction: travelDirection, color: SIMD4(1.0, 0.68, 0.20, 1), lifetime: 0.16, size: 62, rotation: angle)
        case .flameThrower:
            let jitter = SIMD2(Float.random(in: -10...10), Float.random(in: -10...10))
            addStamp(point + jitter, radius: 88, hardness: 0.22, color: SIMD4(1.0, 0.22, 0.025, 0.95), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 18, color: SIMD4(1.0, Float.random(in: 0.42...0.80), 0.16, 0.9), speeds: 70...230, upward: 0, kind: 2, life: 0.35...1.15, size: 10...26, direction: tool.emissionDirection, spread: 0.72)
            addContactEffect(point, tool: tool, direction: tool.emissionDirection, color: SIMD4(1.0, 0.30, 0.025, 1), lifetime: 0.28, size: 105, rotation: angle)
        case .colorThrower:
            let palette: [SIMD4<Float>] = [
                SIMD4(1.0, 0.18, 0.55, 0.92), SIMD4(0.15, 0.82, 1.0, 0.92),
                SIMD4(0.54, 1.0, 0.18, 0.92), SIMD4(1.0, 0.71, 0.10, 0.92),
                SIMD4(0.67, 0.30, 1.0, 0.92)
            ]
            let color = palette.randomElement()!
            addStamp(point, radius: Float.random(in: 72...104), hardness: 0.92, color: color, kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 28, color: color, speeds: 50...260, upward: 0, kind: 5, life: 0.28...0.86, size: 4...12, direction: tool.emissionDirection, spread: 0.94)
            addContactEffect(point, tool: tool, direction: tool.emissionDirection, color: color, lifetime: 0.30, size: 112, rotation: angle)
        case .phaser:
            addStamp(point, radius: 110, hardness: 0.66, color: SIMD4(0.10, 0.78, 1.0, 0.95), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 16, color: SIMD4(0.55, 0.92, 1.0, 1), speeds: 65...270, upward: 0, kind: 6, life: 0.18...0.62, size: 5...14, direction: tool.emissionDirection, spread: 0.62)
            addContactEffect(point, tool: tool, direction: tool.emissionDirection, color: SIMD4(0.20, 0.84, 1.0, 1), lifetime: 0.30, size: 126, rotation: angle)
        case .stamp:
            addStamp(point, radius: 180, hardness: 0.94, color: SIMD4(0.48, 0.16, 0.82, 0.95), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 22, color: SIMD4(0.76, 0.50, 1.0, 1), speeds: 25...180, upward: 30, kind: 0, life: 0.2...0.62, size: 3...8)
            addContactEffect(point, tool: tool, direction: .zero, color: SIMD4(0.68, 0.32, 1.0, 1), lifetime: 0.38, size: 155, rotation: angle)
        case .termites:
            spawnTermites(at: point, count: 12, direction: tool.emissionDirection)
            addContactEffect(point, tool: tool, direction: tool.emissionDirection, color: SIMD4(0.74, 0.42, 0.12, 1), lifetime: 0.34, size: 92, rotation: angle)
        case .washing:
            addStamp(point, radius: 98, hardness: 0.88, color: SIMD4(0.4, 0.82, 1.0, 1), kind: tool.rawValue, rotation: angle)
            addParticles(point, count: 18, color: SIMD4(0.82, 0.96, 1.0, 0.82), speeds: 45...230, upward: 0, kind: 4, life: 0.28...0.86, size: 8...20, direction: tool.emissionDirection, spread: 0.82)
            addContactEffect(point, tool: tool, direction: tool.emissionDirection, color: SIMD4(0.40, 0.86, 1.0, 1), lifetime: 0.28, size: 104, rotation: angle)
        }
    }

    private func addStamp(_ point: SIMD2<Float>, radius: Float, hardness: Float, color: SIMD4<Float>, kind: UInt32, rotation: Float) {
        let assetMix: Float
        switch kind {
        case DestructionTool.hammer.rawValue, DestructionTool.machineGun.rawValue, DestructionTool.stamp.rawValue:
            assetMix = 1
        case DestructionTool.colorThrower.rawValue, DestructionTool.phaser.rawValue:
            assetMix = 0.82
        case DestructionTool.chainsaw.rawValue, DestructionTool.flameThrower.rawValue:
            assetMix = 0.48
        case DestructionTool.termites.rawValue:
            assetMix = 0.78
        default:
            assetMix = 0.70
        }
        pendingStamps.append(DamageStamp(
            point: point,
            radius: radius,
            hardness: hardness,
            color: color,
            kind: kind,
            seed: Float.random(in: 0...1),
            rotation: rotation,
            assetMix: assetMix
        ))
        if kind != DestructionTool.washing.rawValue { marks += 1 }
    }

    private func addParticles(
        _ point: SIMD2<Float>, count: Int, color: SIMD4<Float>, speeds: ClosedRange<Float>,
        upward: Float, kind: UInt32, life: ClosedRange<Float>, size: ClosedRange<Float>,
        direction: SIMD2<Float> = .zero, spread: Float = 2 * .pi
    ) {
        pendingSpawns.append(ParticleSpawn(
            point: point, count: count, color: color,
            minimumSpeed: speeds.lowerBound, maximumSpeed: speeds.upperBound,
            upwardBias: upward, kind: kind, lifetime: life, size: size,
            direction: direction, spread: spread
        ))
    }

    private func addContactEffect(
        _ point: SIMD2<Float>, tool: DestructionTool, direction: SIMD2<Float>,
        color: SIMD4<Float>, lifetime: Float, size: Float, rotation: Float
    ) {
        if contactEffects.count >= Self.maximumContactEffects {
            contactEffects.removeFirst(contactEffects.count - Self.maximumContactEffects + 1)
        }
        contactEffects.append(ContactEffect(
            position: point,
            direction: direction,
            color: color,
            age: 0,
            lifetime: lifetime,
            size: size,
            rotation: rotation,
            kind: tool.rawValue,
            seed: Float.random(in: 0...1)
        ))
    }

    private func emitContinuousToolIfNeeded(now: CFTimeInterval) {
        guard pointerIsDown else { return }
        let interval: CFTimeInterval
        switch selectedTool {
        case .chainsaw: interval = 0.028
        case .machineGun: interval = 0.065
        case .flameThrower: interval = 0.032
        case .colorThrower: interval = 0.09
        case .phaser: interval = 0.045
        case .washing: interval = 0.032
        default: return
        }
        guard now - lastContinuousEmission >= interval else { return }
        trigger(tool: selectedTool, at: pointerPoint, direction: pointerPoint - lastPointerPoint)
        lastContinuousEmission = now
    }

    private func spawnTermites(at point: SIMD2<Float>, count: Int, direction: SIMD2<Float>) {
        let baseDirection = simd_length_squared(direction) > 0.01
            ? simd_normalize(direction)
            : DestructionTool.termites.emissionDirection
        let baseHeading = atan2(baseDirection.y, baseDirection.x)
        let right = SIMD2(baseDirection.y, -baseDirection.x)
        for _ in 0..<count where termites.count < Self.maximumTermites {
            let heading = baseHeading + Float.random(in: -0.92...0.92)
            let offset = baseDirection * Float.random(in: 6...34) + right * Float.random(in: -16...16)
            termites.append(Termite(
                position: point + offset,
                heading: heading,
                speed: Float.random(in: 70...155),
                life: Float.random(in: 18...28),
                chewCooldown: Float.random(in: 0.65...1.50)
            ))
        }
    }

    private func updateTermites(deltaTime: Float, viewport: SIMD2<Float>) {
        guard !termites.isEmpty else { return }
        for index in termites.indices.reversed() {
            termites[index].life -= deltaTime
            if termites[index].life <= 0 {
                termites.remove(at: index)
                continue
            }
            termites[index].heading += Float.random(in: -1.5...1.5) * deltaTime
            var direction = SIMD2(cos(termites[index].heading), sin(termites[index].heading))
            termites[index].position += direction * termites[index].speed * deltaTime

            let margin: Float = 10
            if termites[index].position.x < margin || termites[index].position.x > viewport.x - margin {
                termites[index].heading = .pi - termites[index].heading
                termites[index].position.x = min(max(termites[index].position.x, margin), viewport.x - margin)
            }
            if termites[index].position.y < margin || termites[index].position.y > viewport.y - margin {
                termites[index].heading = -termites[index].heading
                termites[index].position.y = min(max(termites[index].position.y, margin), viewport.y - margin)
            }
            direction = SIMD2(cos(termites[index].heading), sin(termites[index].heading))
            termites[index].chewCooldown -= deltaTime
            if termites[index].chewCooldown <= 0 {
                addStamp(
                    termites[index].position - direction * 7,
                    radius: Float.random(in: 6...10), hardness: 0.72,
                    color: SIMD4(0.07, 0.04, 0.015, 1),
                    kind: DestructionTool.termites.rawValue,
                    rotation: termites[index].heading
                )
                termites[index].chewCooldown = Float.random(in: 2.40...4.20)
            }
        }
    }

    private func writePendingParticles() {
        guard !pendingSpawns.isEmpty else { return }
        let pointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: Self.maximumParticles)
        for spawn in pendingSpawns {
            for _ in 0..<spawn.count {
                let angle: Float
                if simd_length_squared(spawn.direction) > 0.001 {
                    let base = atan2(spawn.direction.y, spawn.direction.x)
                    angle = base + Float.random(in: (-spawn.spread * 0.5)...(spawn.spread * 0.5))
                } else {
                    angle = Float.random(in: 0...(2 * .pi))
                }
                let speed = Float.random(in: spawn.minimumSpeed...spawn.maximumSpeed)
                let velocity = SIMD2(cos(angle) * speed, sin(angle) * speed + spawn.upwardBias)
                let life = Float.random(in: spawn.lifetime)
                pointer[particleCursor] = Particle(
                    position: spawn.point,
                    velocity: velocity,
                    color: spawn.color,
                    life: life,
                    maxLife: life,
                    size: Float.random(in: spawn.size),
                    kind: spawn.kind
                )
                particleCursor = (particleCursor + 1) % Self.maximumParticles
            }
        }
        pendingSpawns.removeAll(keepingCapacity: true)
    }

    private func updateContactEffects(deltaTime: Float) {
        for index in contactEffects.indices.reversed() {
            contactEffects[index].age += deltaTime
            if contactEffects[index].age >= contactEffects[index].lifetime {
                contactEffects.remove(at: index)
            }
        }
    }

    private func writeContactEffects() {
        guard !contactEffects.isEmpty else { return }
        let pointer = contactEffectBuffer.contents().bindMemory(
            to: ContactEffect.self,
            capacity: Self.maximumContactEffects
        )
        for (index, effect) in contactEffects.enumerated() {
            pointer[index] = effect
        }
    }

    private func writeTermiteInstances() {
        guard !termites.isEmpty else { return }
        let pointer = termiteBuffer.contents().bindMemory(to: Particle.self, capacity: Self.maximumTermites)
        for (index, termite) in termites.enumerated() {
            let direction = SIMD2(cos(termite.heading), sin(termite.heading))
            pointer[index] = Particle(
                position: termite.position,
                velocity: direction,
                color: SIMD4(0.18, 0.10, 0.035, 1),
                life: 1,
                maxLife: 1,
                size: 26,
                kind: 3
            )
        }
    }

    private func cursorPose(
        now: CFTimeInterval,
        viewport: SIMD2<Float>
    ) -> (position: SIMD2<Float>, size: Float, rotation: Float, brightness: Float) {
        let age = Float(max(0, now - lastActivationTime))
        let recoil = exp(-age * 10.5)
        let t = Float(now.truncatingRemainder(dividingBy: 1_000))
        var position = pointerPoint
        var rotation: Float = 0
        var scale: Float = 1
        var brightness: Float = 1

        switch selectedTool {
        case .hammer:
            let swing = min(age / 0.42, 1)
            rotation = -0.62 * sin(swing * .pi) * exp(-age * 1.6)
            scale += 0.045 * sin(swing * .pi)
            brightness += 0.20 * recoil
        case .chainsaw:
            let active = pointerIsDown ? 1 as Float : 0.18
            rotation = sin(t * 72) * 0.012 * active
            position += SIMD2(sin(t * 91), cos(t * 83)) * (2.8 * active)
            scale += sin(t * 58) * 0.006 * active
        case .machineGun:
            position -= selectedTool.emissionDirection * (24 * recoil)
            rotation = -0.025 * recoil
            brightness += 0.22 * recoil
        case .flameThrower:
            let active = pointerIsDown ? 1 as Float : 0
            position += SIMD2(sin(t * 47), cos(t * 39)) * (2.1 * active)
            scale += (0.012 + sin(t * 31) * 0.008) * active
            brightness += 0.10 * active
        case .colorThrower:
            position -= selectedTool.emissionDirection * (15 * recoil)
            rotation = 0.018 * sin(t * 22) * (pointerIsDown ? 1 : 0)
            brightness += 0.16 * recoil
        case .phaser:
            let active = pointerIsDown ? 1 as Float : 0.22
            scale += sin(t * 18) * 0.012 * active
            brightness += 0.18 * active + 0.18 * recoil
        case .stamp:
            position.y += 34 * recoil
            scale += 0.025 * recoil
            brightness += 0.10 * recoil
        case .termites:
            position.x += sin(t * 34) * 5 * recoil
            rotation = sin(t * 40) * 0.028 * recoil
        case .washing:
            let active = pointerIsDown ? 1 as Float : 0
            position -= selectedTool.emissionDirection * (10 * active + 13 * recoil)
            rotation = sin(t * 43) * 0.009 * active
            brightness += 0.10 * active
        }

        let baseSize = min(760, max(560, viewport.y * 0.46))
        return (
            position,
            baseSize * selectedTool.cursorScale * scale,
            rotation,
            brightness
        )
    }

    private func publishStats(now: CFTimeInterval) {
        framesSinceStats += 1
        let interval = now - statsStartTime
        guard interval >= 0.75 else { return }
        let fps = Int((Double(framesSinceStats) / interval).rounded())
        onStats?(RenderStats(framesPerSecond: fps, marks: marks, termites: termites.count))
        statsStartTime = now
        framesSinceStats = 0
    }

    private static func loadAssetTexture(named name: String, device: MTLDevice) -> MTLTexture? {
        guard let url = AssetCatalog.url(for: name) else { return nil }
        let texture = try? MTKTextureLoader(device: device).newTexture(
            URL: url,
            options: [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft,
                .generateMipmaps: true
            ]
        )
        texture?.label = name
        return texture
    }

    private static func makeTransparentTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixel: UInt32 = 0
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: MemoryLayout<UInt32>.stride
        )
        return texture
    }

    private static func makeFallbackTexture(device: MTLDevice) throws -> MTLTexture {
        let width = 1_600
        let height = 1_000
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RendererError.particleBuffer }

        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.15, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.15, green: 0.055, blue: 0.22, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.025, green: 0.17, blue: 0.22, alpha: 1).cgColor
            ] as CFArray,
            locations: [0, 0.52, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: height),
            end: CGPoint(x: width, y: 0),
            options: []
        )

        context.setFillColor(NSColor.white.withAlphaComponent(0.055).cgColor)
        for index in 0..<13 {
            let x = CGFloat((index * 257) % width)
            let y = CGFloat((index * 149 + 80) % height)
            context.fillEllipse(in: CGRect(x: x, y: y, width: 210, height: 210))
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.20).cgColor)
        context.fill(CGRect(x: 0, y: height - 34, width: width, height: 34))
        context.setFillColor(NSColor.white.withAlphaComponent(0.72).cgColor)
        for x in stride(from: 24, through: 80, by: 18) {
            context.fillEllipse(in: CGRect(x: x, y: height - 22, width: 8, height: 8))
        }

        let dockRect = CGRect(x: 515, y: 22, width: 570, height: 82)
        context.setFillColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        context.addPath(CGPath(roundedRect: dockRect, cornerWidth: 25, cornerHeight: 25, transform: nil))
        context.fillPath()
        let dockColors: [NSColor] = [.systemBlue, .systemTeal, .systemPink, .systemOrange, .systemPurple, .systemGreen, .systemIndigo]
        for (index, color) in dockColors.enumerated() {
            let rect = CGRect(x: 544 + index * 74, y: 37, width: 52, height: 52)
            context.setFillColor(color.withAlphaComponent(0.85).cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 13, cornerHeight: 13, transform: nil))
            context.fillPath()
        }

        let panel = CGRect(x: 190, y: 235, width: 1_220, height: 600)
        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.72).cgColor)
        context.addPath(CGPath(roundedRect: panel, cornerWidth: 24, cornerHeight: 24, transform: nil))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(NSColor.white.withAlphaComponent(0.055).cgColor)
        context.fill(CGRect(x: 214, y: 278, width: 310, height: 510))
        for row in 0..<7 {
            context.setFillColor(NSColor.white.withAlphaComponent(row == 1 ? 0.18 : 0.075).cgColor)
            let rowRect = CGRect(x: 235, y: 725 - row * 58, width: 265, height: 38)
            context.addPath(CGPath(roundedRect: rowRect, cornerWidth: 11, cornerHeight: 11, transform: nil))
            context.fillPath()
        }
        context.setFillColor(NSColor.white.withAlphaComponent(0.09).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 560, y: 520, width: 370, height: 268), cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor.systemPink.withAlphaComponent(0.35).cgColor)
        context.fillEllipse(in: CGRect(x: 660, y: 565, width: 170, height: 170))
        context.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 962, y: 520, width: 410, height: 268), cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.fillPath()

        guard let image = context.makeImage() else { throw RendererError.particleBuffer }
        let loader = MTKTextureLoader(device: device)
        let texture = try loader.newTexture(
            cgImage: image,
            options: [.SRGB: true, .origin: MTKTextureLoader.Origin.topLeft]
        )
        texture.label = "Synthetic macOS desktop"
        return texture
    }
}
