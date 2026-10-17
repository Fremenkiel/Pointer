import UIKit

/// Switches between the three M1 spikes and shows the live measurements.
final class SpikeViewController: UIViewController {
    private enum Mode: Int, CaseIterable {
        case pencilKit, custom, hybrid
        var title: String { ["PencilKit", "Custom", "Hybrid"][rawValue] }
    }

    private var mode = Mode.custom
    private var settings = SpikeSettings()
    private var canvas: UIView?

    private let modeControl = UISegmentedControl(items: Mode.allCases.map(\.title))
    private let transactionSwitch = UISwitch()
    private let lowLatencySwitch = UISwitch()
    private let filterSwitch = UISwitch()
    private let minCutoffSlider = UISlider()
    private let betaSlider = UISlider()
    private let zoomSlider = UISlider()
    private let valueLabel = UILabel()
    private let statsLabel = UILabel()
    private let bar = UIStackView()
    private var timer: Timer?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Launch argument `-mode 0|1|2` picks the first spike.
        if UserDefaults.standard.object(forKey: "mode") != nil {
            mode = Mode(rawValue: UserDefaults.standard.integer(forKey: "mode")) ?? .custom
        }
        buildBar()
        statsLabel.numberOfLines = 0
        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .systemGreen
        statsLabel.isUserInteractionEnabled = false
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)
        NSLayoutConstraint.activate([
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
        showMode()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStats() }
        }
    }

    private func buildBar() {
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.addAction(UIAction { [weak self] _ in self?.modeChanged() }, for: .valueChanged)
        transactionSwitch.isOn = settings.presentsWithTransaction
        lowLatencySwitch.isOn = settings.lowLatency
        filterSwitch.isOn = settings.filterEnabled
        for control in [transactionSwitch, lowLatencySwitch, filterSwitch] {
            control.addAction(UIAction { [weak self] _ in self?.controlsChanged(resetLog: true) }, for: .valueChanged)
        }
        minCutoffSlider.minimumValue = 0.1
        minCutoffSlider.maximumValue = 10
        minCutoffSlider.value = Float(settings.minCutoff)
        betaSlider.minimumValue = 0
        betaSlider.maximumValue = 0.05
        betaSlider.value = Float(settings.beta)
        zoomSlider.minimumValue = log2(0.25)
        zoomSlider.maximumValue = log2(8)
        zoomSlider.value = 0
        for slider in [minCutoffSlider, betaSlider, zoomSlider] {
            slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
            slider.addAction(UIAction { [weak self] _ in self?.controlsChanged(resetLog: false) }, for: .valueChanged)
        }
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .lightGray

        let clear = UIButton(configuration: .gray(), primaryAction: UIAction(title: "Clear") { [weak self] _ in self?.clear() })
        let save = UIButton(configuration: .gray(), primaryAction: UIAction(title: "Save log") { [weak self] _ in self?.save() })

        let topRow = UIStackView(arrangedSubviews: [
            modeControl, labeled("Transaction", transactionSwitch), labeled("Low latency", lowLatencySwitch),
            labeled("1€", filterSwitch), clear, save,
        ])
        let bottomRow = UIStackView(arrangedSubviews: [
            labeled("min Hz", minCutoffSlider), labeled("beta", betaSlider), labeled("zoom", zoomSlider), valueLabel,
        ])
        for row in [topRow, bottomRow] {
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .center
            bar.addArrangedSubview(row)
        }
        bar.axis = .vertical
        bar.spacing = 8
        bar.alignment = .leading
        bar.isLayoutMarginsRelativeArrangement = true
        bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        bar.backgroundColor = UIColor(white: 0.12, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
        controlsChanged(resetLog: false)
    }

    private func labeled(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12)
        label.textColor = .lightGray
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }

    private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .custom
        showMode()
    }

    private func showMode() {
        canvas?.removeFromSuperview()
        let newCanvas: UIView
        switch mode {
        case .pencilKit:
            newCanvas = PencilKitSpikeView(settings: settings)
        case .custom:
            let custom = CustomCanvasView(frame: .zero)
            custom.settings = customSettings()
            newCanvas = custom
        case .hybrid:
            let hybrid = HybridSpikeView(settings: settings)
            hybrid.onHandoff = { [weak self] in self?.updateStats() }
            newCanvas = hybrid
        }
        newCanvas.frame = view.bounds
        newCanvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(newCanvas, at: 0)
        canvas = newCanvas
        updateStats()
    }

    /// The custom spike runs at zoom 1. Zoom applies to the hybrid only.
    private func customSettings() -> SpikeSettings {
        var custom = settings
        custom.zoom = 1
        return custom
    }

    private func controlsChanged(resetLog: Bool) {
        settings.presentsWithTransaction = transactionSwitch.isOn
        settings.lowLatency = lowLatencySwitch.isOn
        settings.filterEnabled = filterSwitch.isOn
        settings.minCutoff = Double(minCutoffSlider.value)
        settings.beta = Double(betaSlider.value)
        settings.zoom = pow(2, Double(zoomSlider.value))
        valueLabel.text = String(format: "min %.2f Hz  beta %.4f  zoom %.2f", settings.minCutoff, settings.beta, settings.zoom)
        switch canvas {
        case let custom as CustomCanvasView:
            custom.settings = customSettings()
            if resetLog { custom.log.reset() }
        case let hybrid as HybridSpikeView:
            hybrid.settings = settings
            if resetLog { hybrid.log.reset() }
        default:
            break
        }
    }

    private func clear() {
        switch canvas {
        case let custom as CustomCanvasView: custom.clear()
        case let hybrid as HybridSpikeView: hybrid.clear()
        case let pencilKit as PencilKitSpikeView: pencilKit.clear()
        default: break
        }
    }

    private var configurationTitle: String {
        String(
            format: "%@  transaction %@  low latency %@  1€ %@ min %.2f beta %.4f  zoom %.2f",
            mode.title, settings.presentsWithTransaction ? "on" : "off", settings.lowLatency ? "on" : "off",
            settings.filterEnabled ? "on" : "off", settings.minCutoff, settings.beta, settings.zoom)
    }

    private var currentLog: LatencyLog? {
        switch canvas {
        case let custom as CustomCanvasView: custom.log
        case let hybrid as HybridSpikeView: hybrid.log
        default: nil
        }
    }

    private func updateStats() {
        guard let log = currentLog else {
            statsLabel.text = "PencilKit: no presented time is available. Measure with the camera."
            return
        }
        statsLabel.text = log.summary(title: configurationTitle)
    }

    private func save() {
        guard let log = currentLog, let folder = log.write(name: configurationTitle) else { return }
        statsLabel.text = "Saved to Files > On My iPad > LatencySpikes > \(folder.lastPathComponent)"
    }
}
