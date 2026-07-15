import AVFoundation

/// Low-latency tool audio with separate one-shot and held-tool paths.
/// Continuous tools own one loop at a time; rapid tools use a short timer so
/// their cadence stays audible without tying audio scheduling to GPU frames.
final class ToolSoundController: NSObject, AVAudioPlayerDelegate {
    private var loopPlayer: AVAudioPlayer?
    private var oneShotPlayers: [AVAudioPlayer] = []
    private var repetitionTimer: Timer?
    private var activeTool: DestructionTool?

    func begin(_ tool: DestructionTool) {
        stopHeldSound()
        activeTool = tool

        switch tool {
        case .hammer:
            playOneShot("hammer.wav", volume: 0.86, rate: 0.94...1.04)
        case .chainsaw:
            startLoop("chainsaw.wav", volume: 0.62, rate: 0.98)
        case .machineGun:
            playOneShot("machine.wav", volume: 0.62, rate: 0.96...1.04)
            startRepeating("machine.wav", interval: 0.105, volume: 0.58, rate: 0.94...1.06)
        case .flameThrower:
            startLoop("flame.wav", volume: 0.50, rate: 1.0)
        case .colorThrower:
            playOneShot("color.wav", volume: 0.64, rate: 0.92...1.08)
            startRepeating("color.wav", interval: 0.24, volume: 0.48, rate: 0.90...1.10)
        case .phaser:
            playOneShot("phaser.wav", volume: 0.70, rate: 0.96...1.03)
            startLoop("phaser-hum.wav", volume: 0.27, rate: 1.0)
        case .stamp:
            playOneShot("stamp.wav", volume: 0.76, rate: 0.92...1.02)
        case .termites:
            playOneShot("termites.wav", volume: 0.52, rate: 0.90...1.08)
        case .washing:
            startLoop("washing.wav", volume: 0.48, rate: 1.0)
        }
    }

    func end() {
        stopHeldSound()
    }

    func stopAll() {
        stopHeldSound()
        for player in oneShotPlayers {
            player.stop()
        }
        oneShotPlayers.removeAll(keepingCapacity: true)
    }

    private func startRepeating(
        _ filename: String,
        interval: TimeInterval,
        volume: Float,
        rate: ClosedRange<Float>
    ) {
        repetitionTimer?.invalidate()
        repetitionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.playOneShot(filename, volume: volume, rate: rate)
        }
        if let repetitionTimer {
            RunLoop.main.add(repetitionTimer, forMode: .common)
        }
    }

    private func startLoop(_ filename: String, volume: Float, rate: Float) {
        guard let url = AssetCatalog.soundURL(for: filename),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = volume
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        player.play()
        loopPlayer = player
    }

    private func playOneShot(
        _ filename: String,
        volume: Float,
        rate: ClosedRange<Float>
    ) {
        guard let url = AssetCatalog.soundURL(for: filename),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        oneShotPlayers.removeAll { !$0.isPlaying }
        player.delegate = self
        player.volume = volume
        player.enableRate = true
        player.rate = Float.random(in: rate)
        player.prepareToPlay()
        player.play()
        oneShotPlayers.append(player)
    }

    private func stopHeldSound() {
        activeTool = nil
        repetitionTimer?.invalidate()
        repetitionTimer = nil

        guard let player = loopPlayer else { return }
        loopPlayer = nil
        player.setVolume(0, fadeDuration: 0.10)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            player.stop()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        oneShotPlayers.removeAll { $0 === player }
    }
}
