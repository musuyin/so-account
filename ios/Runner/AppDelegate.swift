import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SoAccountUpdates") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "dev.soaccount/updates", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "info":
        result([
          "platform": "ios",
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
          "build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        ])
      case "openRelease":
        guard let args = call.arguments as? [String: Any],
          let value = args["url"] as? String, let url = URL(string: value),
          url.scheme == "https", url.host == "github.com",
          url.path == "/musuyin/so-account/releases" ||
            url.path.hasPrefix("/musuyin/so-account/releases/tag/v") else {
          result(FlutterError(code: "UPDATE_URL", message: "发布页面地址无效", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened { result(nil) }
          else { result(FlutterError(code: "UPDATE_URL", message: "无法打开发布页面", details: nil)) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
