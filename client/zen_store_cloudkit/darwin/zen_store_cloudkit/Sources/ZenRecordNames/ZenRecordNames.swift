import CryptoKit
import Foundation
import Security

/// What CloudKit is allowed to see as a record's name: an HMAC of the store's own name
/// (`<collection>:<id>`) under a key only the person's devices hold (ADR-083).
///
/// A plain name tells Apple which collections exist, how many records each holds, and any id an
/// application derives from data (a month, a date). The shared-folder transport hides all of that
/// (ADR-076); this makes the two transports equal. The plain name travels inside the record's
/// encrypted state instead, so a device that fetches a record can still tell which one it is.
///
/// This type imports nothing from Flutter, so the naming can be tested without the plugin.
public struct ZenRecordNames: Sendable {
  private let key: SymmetricKey

  public init(key: SymmetricKey) {
    self.key = key
  }

  /// The CloudKit record name for [name]: 64 lower-case hex digits, the same on every device that
  /// holds the key and different for every name.
  public func hashed(_ name: String) -> String {
    let code = HMAC<SHA256>.authenticationCode(for: Data("zen_store_cloudkit.record:\(name)".utf8), using: key)
    return code.map { String(format: "%02x", $0) }.joined()
  }

  /// The key shared by the person's devices: a Keychain item marked synchronizable, so iCloud
  /// Keychain carries it end to end encrypted. Created on first use.
  ///
  /// Two devices that both start before the item has synced each create their own; iCloud Keychain
  /// then keeps one. Records written under the other key stay in the zone under names no device
  /// derives any more, and carry the same plain name, so the store merges them as the same record.
  public static func loadKey(account: String) throws -> SymmetricKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "zen_store_cloudkit.record_names",
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
    ]
    var found: CFTypeRef?
    var status = SecItemCopyMatching(query.merging([kSecReturnData as String: true]) { $1 } as CFDictionary, &found)
    if status == errSecSuccess, let data = found as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard status == errSecItemNotFound else { throw ZenRecordNamesError.keychain(status) }
    let fresh = SymmetricKey(size: .bits256)
    let add = fresh.withUnsafeBytes { bytes in
      query.merging([
        kSecValueData as String: Data(bytes),
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]) { $1 }
    }
    status = SecItemAdd(add as CFDictionary, nil)
    if status == errSecDuplicateItem { return try loadKey(account: account) }
    guard status == errSecSuccess else { throw ZenRecordNamesError.keychain(status) }
    return fresh
  }
}

public enum ZenRecordNamesError: Error, LocalizedError {
  case keychain(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .keychain(let status): return "the record-name key could not be read or saved in the iCloud Keychain (OSStatus \(status))"
    }
  }
}
