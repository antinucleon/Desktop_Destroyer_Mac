import AppKit
import simd

enum DestructionTool: UInt32, CaseIterable, Sendable {
    case hammer = 0
    case chainsaw
    case machineGun
    case flameThrower
    case colorThrower
    case phaser
    case stamp
    case termites
    case washing

    var shortcut: String { String(Int(rawValue) + 1) }

    var name: String {
        switch self {
        case .hammer: "Hammer"
        case .chainsaw: "Chain-saw"
        case .machineGun: "Machine gun"
        case .flameThrower: "Flame"
        case .colorThrower: "Color"
        case .phaser: "Phaser"
        case .stamp: "Stamp"
        case .termites: "Termites"
        case .washing: "Washing"
        }
    }

    var shortName: String {
        switch self {
        case .machineGun: "Machine"
        case .flameThrower: "Flame"
        case .colorThrower: "Color"
        default: name
        }
    }

    var symbolName: String {
        switch self {
        case .hammer: "hammer.fill"
        case .chainsaw: "gearshape.2.fill"
        case .machineGun: "scope"
        case .flameThrower: "flame.fill"
        case .colorThrower: "paintpalette.fill"
        case .phaser: "bolt.horizontal.fill"
        case .stamp: "seal.fill"
        case .termites: "ant.fill"
        case .washing: "drop.triangle.fill"
        }
    }

    var accent: SIMD4<Float> {
        switch self {
        case .hammer: SIMD4(1.00, 0.38, 0.25, 1)
        case .chainsaw: SIMD4(1.00, 0.70, 0.20, 1)
        case .machineGun: SIMD4(0.72, 0.76, 0.82, 1)
        case .flameThrower: SIMD4(1.00, 0.29, 0.08, 1)
        case .colorThrower: SIMD4(0.94, 0.25, 0.75, 1)
        case .phaser: SIMD4(0.25, 0.82, 1.00, 1)
        case .stamp: SIMD4(0.65, 0.45, 1.00, 1)
        case .termites: SIMD4(0.75, 0.51, 0.26, 1)
        case .washing: SIMD4(0.24, 0.72, 1.00, 1)
        }
    }

    var help: String {
        switch self {
        case .hammer: "Click for a heavy radial impact"
        case .chainsaw: "Drag to carve a jagged cut"
        case .machineGun: "Hold to pepper the surface"
        case .flameThrower: "Drag to paint fire and soot"
        case .colorThrower: "Click or drag to throw color"
        case .phaser: "Hold for a neon energy burn"
        case .stamp: "Click to leave a bold seal"
        case .termites: "Click to release a hungry swarm"
        case .washing: "Drag to clean damage away"
        }
    }

    var color: NSColor {
        NSColor(
            calibratedRed: CGFloat(accent.x),
            green: CGFloat(accent.y),
            blue: CGFloat(accent.z),
            alpha: CGFloat(accent.w)
        )
    }

    /// Registration point inside each generated 3×3 cursor-atlas cell.
    /// Coordinates use the image convention (top-left is 0,0). Keeping the
    /// action point explicit lets Metal place the hammer face, blade, muzzle,
    /// stamp plate, and nozzles exactly on the gameplay coordinate.
    var cursorActionAnchor: SIMD2<Float> {
        switch self {
        case .hammer: SIMD2(0.126, 0.199)
        case .chainsaw: SIMD2(0.075, 0.078)
        case .machineGun: SIMD2(0.095, 0.127)
        case .flameThrower: SIMD2(0.094, 0.084)
        case .colorThrower: SIMD2(0.216, 0.170)
        case .phaser: SIMD2(0.106, 0.097)
        case .stamp: SIMD2(0.404, 0.630)
        case .termites: SIMD2(0.224, 0.161)
        case .washing: SIMD2(0.148, 0.139)
        }
    }

    /// Direction in which a muzzle/nozzle-driven effect leaves the registered
    /// action point. The generated first-person tools all aim toward upper-left.
    var emissionDirection: SIMD2<Float> {
        switch self {
        case .chainsaw: simd_normalize(SIMD2(-0.90, 0.42))
        case .machineGun: simd_normalize(SIMD2(-0.92, 0.38))
        case .flameThrower: simd_normalize(SIMD2(-0.82, 0.57))
        case .colorThrower: simd_normalize(SIMD2(-0.84, 0.54))
        case .phaser: simd_normalize(SIMD2(-0.84, 0.54))
        case .termites: simd_normalize(SIMD2(-0.84, 0.54))
        case .washing: simd_normalize(SIMD2(-0.82, 0.57))
        default: .zero
        }
    }

    /// The two direction-sensitive tools use standalone high-resolution art
    /// instead of the legacy atlas cells, which contained baked-in effects.
    var standaloneCursorAssetName: String? {
        switch self {
        case .colorThrower: "cursor-paint-v2.png"
        case .termites: "cursor-termite-v2.png"
        default: nil
        }
    }

    var cursorScale: Float {
        switch self {
        case .chainsaw: 1.08
        case .stamp: 0.94
        case .termites: 0.98
        default: 1
        }
    }
}
