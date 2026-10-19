import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1240, height: 820)
    self.minSize = NSSize(width: 860, height: 600)
    self.setFrame(windowFrame, display: true)
    self.center()
    self.title = "RentManager"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }

    // Liquid Glass / Vibrancy Configuration
    self.isOpaque = false
    self.backgroundColor = .clear
    flutterViewController.backgroundColor = .clear

    let visualEffectView = NSVisualEffectView()
    visualEffectView.material = .sidebar
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = .active
    visualEffectView.autoresizingMask = [.width, .height]

    if let contentView = self.contentView {
      visualEffectView.frame = contentView.bounds
      contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
    }

    // Hide native window controller buttons so Flutter custom buttons can be used
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true

    // Flutter MethodChannel for custom window controller actions
    let windowChannel = FlutterMethodChannel(
      name: "com.nazelahi.rentmanager/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "close":
        self.performClose(nil)
        result(true)
      case "minimize":
        self.miniaturize(nil)
        result(true)
      case "toggleFullScreen":
        self.toggleFullScreen(nil)
        result(true)
      case "zoom":
        self.zoom(nil)
        result(true)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
