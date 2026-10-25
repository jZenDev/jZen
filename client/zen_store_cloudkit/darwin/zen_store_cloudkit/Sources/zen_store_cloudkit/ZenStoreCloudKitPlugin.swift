#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import Foundation

/// The channel's entry point. The sync itself is `ZenCloudKitBridge`; this class only routes
/// calls, and sets Data Protection on the store's directory, which needs no CloudKit at all.
public class ZenStoreCloudKitPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var bridge: ZenCloudKitBridge?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "zen_store_cloudkit", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(ZenStoreCloudKitPlugin(channel: channel), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "protectDirectory":
      guard let path = arguments["path"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "path is required", details: nil))
        return
      }
      result(Self.protect(directory: URL(fileURLWithPath: path, isDirectory: true)))
    case "start":
      let zone = arguments["zone"] as? String ?? "zen_store"
      let state = (arguments["state"] as? FlutterStandardTypedData)?.data
      let bridge = ZenCloudKitBridge(
        channel: channel,
        containerId: arguments["containerId"] as? String,
        zone: zone,
        state: state
      )
      self.bridge = bridge
      Task {
        await bridge.start()
        DispatchQueue.main.async { result(nil) }
      }
    case "changed":
      bridge?.changed(arguments["names"] as? [String] ?? [])
      result(nil)
    case "syncNow":
      guard let bridge else {
        result(FlutterError(code: "not_started", message: "sync was not started", details: nil))
        return
      }
      Task {
        let error = await bridge.syncNow()
        DispatchQueue.main.async {
          result(error.map { FlutterError(code: "sync_failed", message: $0, details: nil) })
        }
      }
    case "stop":
      bridge?.stop()
      bridge = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Data Protection `complete` on the directory and everything in it: unreadable while the device
  /// is locked. New files take their directory's class, so the store's later writes are covered.
  /// macOS has no such class for app files, so it reports false and the store's own encryption is
  /// the protection there.
  private static func protect(directory: URL) -> Any {
    #if os(iOS)
    let manager = FileManager.default
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
      try manager.setAttributes(attributes, ofItemAtPath: directory.path)
      if let items = manager.enumerator(atPath: directory.path) {
        for case let item as String in items {
          try manager.setAttributes(attributes, ofItemAtPath: directory.appendingPathComponent(item).path)
        }
      }
      return true
    } catch {
      return FlutterError(code: "protect_failed", message: error.localizedDescription, details: directory.path)
    }
    #else
    return false
    #endif
  }
}
