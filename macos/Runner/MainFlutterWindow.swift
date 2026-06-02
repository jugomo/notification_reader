import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let badgeChannel = FlutterMethodChannel(
      name: "com.example.notification_reader/badge",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    badgeChannel.setMethodCallHandler { (call, result) in
      if call.method == "setBadge" {
        let count = call.arguments as? Int ?? 0
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
