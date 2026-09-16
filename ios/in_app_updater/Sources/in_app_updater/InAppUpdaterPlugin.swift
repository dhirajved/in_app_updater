import Flutter
import StoreKit
import UIKit

private let methodChannelName = "in_app_updater/methods"

/// Apple has no in-app self-update API; this compares the running app's
/// version against the live App Store listing via the public lookup endpoint.
public class InAppUpdaterPlugin: NSObject, FlutterPlugin, SKStoreProductViewControllerDelegate {
  private var appStoreUrl: URL?
  private var appStoreTrackId: Int?
  private var pendingOpenStoreResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
    let instance = InAppUpdaterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkForUpdate":
      checkForUpdate(result: result)
    case "openStore":
      openStore(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkForUpdate(result: @escaping FlutterResult) {
    guard let bundleId = Bundle.main.bundleIdentifier,
      let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      let lookupUrl = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)")
    else {
      result(FlutterError(code: "BAD_CONFIG", message: "Missing bundle id or app version", details: nil))
      return
    }

    URLSession.shared.dataTask(with: lookupUrl) { [weak self] data, _, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "CHECK_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let data = data,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let entries = json["results"] as? [[String: Any]],
        let entry = entries.first,
        let latestVersion = entry["version"] as? String,
        let trackId = entry["trackId"] as? Int,
        let trackViewUrlString = entry["trackViewUrl"] as? String,
        let trackViewUrl = URL(string: trackViewUrlString)
      else {
        DispatchQueue.main.async {
          result(FlutterError(code: "PARSE_FAILED", message: "Unexpected App Store lookup response", details: nil))
        }
        return
      }

      self?.appStoreUrl = trackViewUrl
      self?.appStoreTrackId = trackId
      let updateAvailable = latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending

      DispatchQueue.main.async {
        result([
          "updateAvailable": updateAvailable,
          "currentVersion": currentVersion,
          "latestVersion": latestVersion,
          "storeUrl": trackViewUrlString,
        ])
      }
    }.resume()
  }

  /// Presents the App Store listing as an in-app modal sheet (StoreKit) rather
  /// than switching to the App Store app. Falls back to UIApplication.open if
  /// no top view controller is available to present from.
  private func openStore(result: @escaping FlutterResult) {
    guard let trackId = appStoreTrackId else {
      result(FlutterError(code: "NO_URL", message: "Call checkForUpdate before openStore", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self = self, let topViewController = Self.topViewController() else {
        self?.openStoreUrlFallback(result: result)
        return
      }

      self.pendingOpenStoreResult = result
      let storeViewController = SKStoreProductViewController()
      storeViewController.delegate = self

      let parameters = [SKStoreProductParameterITunesItemIdentifier: String(trackId)]
      storeViewController.loadProduct(withParameters: parameters) { [weak self] success, error in
        if !success {
          self?.pendingOpenStoreResult = nil
          self?.openStoreUrlFallback(result: result)
          return
        }
        topViewController.present(storeViewController, animated: true)
      }
    }
  }

  private func openStoreUrlFallback(result: @escaping FlutterResult) {
    guard let url = appStoreUrl else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { success in
      result(success)
    }
  }

  private static func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController
  ) -> UIViewController? {
    if let nav = base as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
      return topViewController(base: selected)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }

  // MARK: - SKStoreProductViewControllerDelegate

  public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    viewController.dismiss(animated: true)
    pendingOpenStoreResult?(true)
    pendingOpenStoreResult = nil
  }
}
