/// Whether everything the engine delivered has reached the store's side, which decides whether the
/// engine's state may still be saved (ADR-088).
///
/// The state holds the change token. Saved after a change that went nowhere, it says that change
/// arrived, and CloudKit never sends it again. So once one is lost, this engine's state is not
/// saved again: the next launch starts from the last saved one and fetches the change anew.
///
/// A change the store could not write yet is not lost. The Dart side takes it, answers `true`, and
/// holds the state behind it until it is written.
public struct ZenDeliveryLedger {
  /// Whether a change was lost since this engine started. Nothing sets it back.
  public private(set) var hasLostAChange = false

  public init() {}

  /// Notes Dart's reply to a change for the store, and returns whether Dart took it. Only `true`
  /// does: a `FlutterError`, `FlutterMethodNotImplemented` or no value means it did not.
  public mutating func took(_ reply: Any?) -> Bool {
    if reply as? Bool == true { return true }
    lose()
    return false
  }

  /// Notes a delivered change that could not be handed to Dart at all.
  public mutating func lose() {
    hasLostAChange = true
  }

  public var maySaveState: Bool { !hasLostAChange }

  /// Whether the engine's status [state] may be shown. After a loss, no report of progress may
  /// replace the failure; another failure may.
  public func mayReport(_ state: String) -> Bool {
    !hasLostAChange || state == "unavailable"
  }
}
