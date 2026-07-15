# Desktop Destroyer — Metal Edition

A native macOS interpretation of the 1999 desktop stress toy. It recreates the original nine-tool loop with a modern AppKit interface, persistent procedural damage, autonomous termites, reversible washing, ScreenCaptureKit backgrounds, and a Metal renderer designed for Retina displays.

## What is included

- The original tool palette: Hammer, Chain-saw, Machine gun, Flame-thrower, Color-thrower, Phaser, Stamp, Termites, and Washing.
- Registered, high-resolution damage art for cracks, horizontal saw gouges, single bullet holes, soot, paint, energy burns, termite bites, and cleaning masks.
- A Metal compute particle simulation with directional cones, spinning debris, expanding droplets, sparks, embers, energy motes, and soap bubbles.
- Time-based Metal animation for a full hammer swing with concentric impact waves, chainsaw vibration, gun recoil, nozzle pulsing, stamp travel, phaser rings, splash/foam bursts, and a 12 FPS termite walk cycle.
- Tool-aware CC0 sound design with one-shots, rapid-fire cadence, held-tool loops, pitch variation, and short release fades.
- Per-tool action anchors keep the hammer face, saw tip, muzzle, stamp plate, canister opening, and nozzles on the exact damage coordinate; Color and Termites use the same fixed upper-left first-person pose as Phaser.
- A generated production art pack with nine held-tool cursors, eight registered damage decals, eight particle sprites, a biologically recognizable eight-frame worker-termite walk cycle, sixteen rubber stamps, and a native macOS app icon.
- A persistent 16-bit floating-point destruction surface. The real desktop and its files are never modified.
- ScreenCaptureKit integration to use the current display as a static background.
- Keyboard selection with `1`–`9`, `C` to capture, and `R` to reset.

## Build and run

The project requires macOS 14 or newer and Xcode command-line tools.

```sh
./scripts/package_app.sh
open "build/Desktop Destroyer.app"
```

For development, `swift run DesktopDestroyer` also works, though the packaged app provides the correct identity for Screen Recording permission.

On the first desktop capture, the app opens Privacy & Security → Screen & System Audio Recording when permission is unavailable. If Desktop Destroyer is not listed, click `+` and select `Desktop Destroyer.app`, enable it, then quit and reopen the app. For a durable permission entry, place the app in `/Applications` before adding it; development builds inside `build/` may be replaced during packaging. The capture is a single static image used only inside the destruction canvas.

## Renderer architecture

1. ScreenCaptureKit or the built-in synthetic macOS scene supplies the immutable background texture.
2. Bounded Metal compute dispatches combine authored decal-atlas samples with procedural breakup and write them into a persistent RGBA16Float texture.
3. A GPU particle buffer is advanced by a second compute kernel every frame, while termite atlas frames advance from elapsed time rather than position.
4. One render pass composites the background and damage surface, draws textured particles, animated contact effects, termites, and a registered held-tool cursor.

Damage is entirely reversible: Washing edits only the in-memory mask, while Reset clears the mask and transient simulation state.
