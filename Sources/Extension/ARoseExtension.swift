import AppKit
import ScreenSaver
import OSLog

private let extensionLog = Logger(subsystem: "cz.coolajz.ARose", category: "Extension")

@objc(ARoseExtension)
final class ARoseExtension: ScreenSaverExtension {}

@objc(ARoseExtensionViewController)
final class ARoseExtensionViewController: ScreenSaverViewController {
    override func loadView() {
        // ViewBridge supplies the actual bounds and sets ScreenSaverView's
        // preview flag before starting animation. NSScreen.main cannot identify
        // previews because it describes the whole display in both processes.
        extensionLog.notice("Loading screen saver view")
        let saver = ARoseView(frame: NSRect(x: 0, y: 0, width: 640, height: 400),
                              isPreview: false, settings: .standard)!
        saver.showsIdlePreview = true
        view = saver
    }
}

@objc(ARoseConfigurationViewController)
final class ARoseConfigurationViewController: ScreenSaverConfigurationViewController {
    private var options: RoseOptions?

    override func loadView() {
        extensionLog.notice("Loading configuration controller")
        let defaults = UserDefaults.standard
        defaults.register(defaults: ARoseView.initialSettings)
        let options = RoseOptions(defaults: defaults) {}
        self.options = options
        options.dismissHandler = { [weak self] in
            self?.configureSheetDidEnd()
        }
        view = options.contentViewController.view
        preferredContentSize = options.contentViewController.preferredContentSize
        options.reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        options?.reload()
    }

    override func configureSheetWillPresent() {
        super.configureSheetWillPresent()
        options?.reload()
    }
}
