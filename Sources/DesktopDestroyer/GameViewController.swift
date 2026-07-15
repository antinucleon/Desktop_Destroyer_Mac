import AppKit
import MetalKit
import ScreenCaptureKit

@MainActor
final class GameViewController: NSViewController {
    private var metalView: DestroyerMetalView!
    private var toolButtons: [DestructionTool: ToolButton] = [:]
    private var selectedTool: DestructionTool = .hammer
    private let activityLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private let selectedToolLabel = NSTextField(labelWithString: "")
    private let captureButton = NSButton()

    override func loadView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let label = NSTextField(wrappingLabelWithString: "Desktop Destroyer requires a Mac with Metal support.")
            label.alignment = .center
            view = label
            return
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1_180, height: 760))
        container.wantsLayer = true
        view = container
        preferredContentSize = container.frame.size

        do {
            metalView = try DestroyerMetalView(frame: .zero, device: device)
        } catch {
            let label = NSTextField(wrappingLabelWithString: "Metal renderer could not start:\n\(error.localizedDescription)")
            label.alignment = .center
            container.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
            ])
            return
        }

        metalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: container.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        buildHeader(in: container)
        buildToolPalette(in: container)
        wireRenderer()
        selectTool(.hammer)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(metalView)
    }

    func resetSurface() {
        metalView?.stopAllSounds()
        metalView?.renderer.clear()
        activityLabel.stringValue = "Surface restored — nothing on your Mac was changed"
        refocusCanvas()
    }

    func captureDesktop() {
        guard metalView != nil else { return }
        metalView.stopAllSounds()
        captureButton.isEnabled = false
        activityLabel.stringValue = "Capturing the display beneath Desktop Destroyer…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.captureButton.isEnabled = true }
            do {
                let image = try await self.captureDisplayImage()
                try self.metalView.renderer.setBackground(image)
                self.activityLabel.stringValue = "Desktop captured — all destruction remains inside this app"
            } catch {
                self.activityLabel.stringValue = "Capture unavailable. Allow Screen Recording in System Settings, then try again."
            }
            self.refocusCanvas()
        }
    }

    private func buildHeader(in container: NSView) {
        let panel = makeGlassPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(panel)

        let title = NSTextField(labelWithString: "DESKTOP DESTROYER")
        title.font = .systemFont(ofSize: 14, weight: .heavy)
        title.textColor = .white
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        activityLabel.stringValue = "Press 1–9 · drag to destroy · C captures your real desktop"
        activityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        activityLabel.textColor = NSColor.white.withAlphaComponent(0.64)
        activityLabel.lineBreakMode = .byTruncatingTail

        let titleStack = NSStackView(views: [title, activityLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        var brandViews: [NSView] = []
        if let icon = AssetCatalog.image(named: "app-icon.png") {
            let iconView = NSImageView(image: icon)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.wantsLayer = true
            iconView.layer?.cornerRadius = 9
            iconView.layer?.cornerCurve = .continuous
            iconView.layer?.masksToBounds = true
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 38),
                iconView.heightAnchor.constraint(equalToConstant: 38)
            ])
            brandViews.append(iconView)
        }
        brandViews.append(titleStack)
        let brandStack = NSStackView(views: brandViews)
        brandStack.orientation = .horizontal
        brandStack.alignment = .centerY
        brandStack.spacing = 10

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        statsLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        statsLabel.stringValue = "METAL · 120 HZ"

        captureButton.title = "Capture Desktop"
        captureButton.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        captureButton.imagePosition = .imageLeading
        captureButton.bezelStyle = .texturedRounded
        captureButton.target = self
        captureButton.action = #selector(captureClicked)
        captureButton.toolTip = "Capture the current display as a safe, static background (C)"

        let resetButton = NSButton(
            title: "Reset",
            image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: #selector(resetClicked)
        )
        resetButton.imagePosition = .imageLeading
        resetButton.bezelStyle = .texturedRounded
        resetButton.keyEquivalent = "r"
        resetButton.keyEquivalentModifierMask = [.command]

        let actions = NSStackView(views: [statsLabel, captureButton, resetButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        panel.addSubview(brandStack)
        panel.addSubview(actions)
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            panel.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            panel.heightAnchor.constraint(equalToConstant: 58),
            brandStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            brandStack.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: brandStack.trailingAnchor, constant: 18),
            actions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            actions.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
        ])
    }

    private func buildToolPalette(in container: NSView) {
        let panel = makeGlassPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(panel)

        selectedToolLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        selectedToolLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        selectedToolLabel.alignment = .center

        var buttons: [NSView] = []
        for tool in DestructionTool.allCases {
            let button = ToolButton(tool: tool, target: self, action: #selector(toolClicked(_:)))
            toolButtons[tool] = button
            buttons.append(button)
        }
        let buttonStack = NSStackView(views: buttons)
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 5
        buttonStack.distribution = .fillEqually

        let stack = NSStackView(views: [selectedToolLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        panel.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -9)
        ])
    }

    private func makeGlassPanel() -> NSVisualEffectView {
        let panel = NSVisualEffectView()
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 18
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        panel.layer?.masksToBounds = true
        return panel
    }

    private func wireRenderer() {
        metalView.onToolShortcut = { [weak self] tool in self?.selectTool(tool) }
        metalView.onResetShortcut = { [weak self] in self?.resetSurface() }
        metalView.onCaptureShortcut = { [weak self] in self?.captureDesktop() }
        metalView.renderer.onStats = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statsLabel.stringValue = "METAL · \(stats.framesPerSecond) FPS · \(stats.marks) MARKS · \(stats.termites) TERMITES"
            }
        }
    }

    private func selectTool(_ tool: DestructionTool) {
        selectedTool = tool
        metalView?.renderer.select(tool)
        for (candidate, button) in toolButtons {
            button.isSelected = candidate == tool
        }
        selectedToolLabel.stringValue = "\(tool.shortcut) · \(tool.name.uppercased()) — \(tool.help)"
        selectedToolLabel.textColor = tool.color
        refocusCanvas()
    }

    private func refocusCanvas() {
        view.window?.makeFirstResponder(metalView)
    }

    private func captureDisplayImage() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (view.window?.screen?.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let ownApplication = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplication.map { [$0] } ?? [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.captureResolution = .best
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    @objc private func toolClicked(_ sender: ToolButton) {
        selectTool(sender.tool)
    }

    @objc private func resetClicked() {
        resetSurface()
    }

    @objc private func captureClicked() {
        captureDesktop()
    }
}

private enum CaptureError: Error {
    case noDisplay
}

final class ToolButton: NSButton {
    let tool: DestructionTool

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(tool: DestructionTool, target: AnyObject?, action: Selector?) {
        self.tool = tool
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = "\(tool.shortcut)  \(tool.shortName)"
        image = AssetCatalog.toolThumbnail(for: tool)
            ?? NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.name)
        image?.isTemplate = false
        imagePosition = .imageAbove
        imageScaling = .scaleProportionallyDown
        font = .systemFont(ofSize: 9.5, weight: .semibold)
        isBordered = false
        toolTip = "\(tool.shortcut) — \(tool.help)"
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 72),
            heightAnchor.constraint(equalToConstant: 50)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func updateAppearance() {
        contentTintColor = isSelected ? tool.color : NSColor.white.withAlphaComponent(0.74)
        layer?.backgroundColor = isSelected
            ? tool.color.withAlphaComponent(0.18).cgColor
            : NSColor.white.withAlphaComponent(0.035).cgColor
        layer?.borderWidth = isSelected ? 1 : 0.5
        layer?.borderColor = isSelected
            ? tool.color.withAlphaComponent(0.55).cgColor
            : NSColor.white.withAlphaComponent(0.08).cgColor
    }
}
