import CloudKit
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import Foundation

/// `CKSyncEngine` against the user's private database, with the store on the Dart side as the
/// source of truth.
///
/// Each store record is one CloudKit record named `<collection>:<id>` in one custom zone, whose
/// whole state is a single field in `encryptedValues`: CloudKit encrypts it on the device with keys
/// in the user's iCloud Keychain, so Apple holds only ciphertext. The engine owns the sync loop —
/// what to send, batching, retries, push-triggered fetches, change tokens — and this class only
/// translates: it asks Dart for payloads to send, hands Dart what was fetched, confirms saves, and
/// returns the server's copy when a save was refused because it changed, for Dart to merge.
///
/// Every call into Dart is awaited before the engine moves on, so a change token is never saved
/// for records the store has not yet written to disk.
final class ZenCloudKitBridge: CKSyncEngineDelegate, @unchecked Sendable {
  private static let recordType = "ZenRecord"
  private static let stateField = "state"

  private let channel: FlutterMethodChannel
  private let container: CKContainer
  private let zoneID: CKRecordZone.ID
  private let initialState: CKSyncEngine.State.Serialization?
  private var engine: CKSyncEngine?
  private var stopped = false

  init(channel: FlutterMethodChannel, containerId: String?, zone: String, state: Data?) {
    self.channel = channel
    container = containerId.map { CKContainer(identifier: $0) } ?? CKContainer.default()
    zoneID = CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
    initialState = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
  }

  func start() async {
    do {
      let account = try await container.accountStatus()
      if account != .available {
        await status("unavailable", issue: "noAccount", message: "iCloud account status: \(account.rawValue)")
      }
    } catch {
      await status("unavailable", issue: "other", message: error.localizedDescription)
    }
    let configuration = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: initialState,
      delegate: self
    )
    let engine = CKSyncEngine(configuration)
    if initialState == nil {
      engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }
    self.engine = engine
  }

  func changed(_ names: [String]) {
    guard let engine, !stopped else { return }
    engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID($0)) })
  }

  /// Sends what is waiting, then fetches; the error's description, or nil.
  func syncNow() async -> String? {
    guard let engine, !stopped else { return nil }
    do {
      try await engine.sendChanges()
      try await engine.fetchChanges()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  func stop() {
    stopped = true
    engine = nil
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case .stateUpdate(let update):
      if let data = try? JSONEncoder().encode(update.stateSerialization) {
        _ = await callDart("state", ["state": FlutterStandardTypedData(bytes: data)])
      }

    case .accountChange(let change):
      switch change.changeType {
      case .signIn:
        await status("syncing")
      case .signOut:
        await status("unavailable", issue: "noAccount", message: "signed out of iCloud")
      case .switchAccounts:
        // Never send one person's records into another person's account.
        stop()
        await status("unavailable", issue: "accountChanged", message: "the iCloud account changed")
      @unknown default:
        break
      }

    case .fetchedDatabaseChanges(let changes):
      for deletion in changes.deletions where deletion.zoneID == zoneID {
        switch deletion.reason {
        case .encryptedDataReset:
          // The user's iCloud Keychain was reset: the old ciphertext is unreadable by anyone.
          // Start the zone again and send everything this device holds.
          _ = await callDart("resetCloud", nil)
          syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
          await status("syncing", message: "iCloud Keychain was reset; uploading again")
        default:
          // Deleted or purged from Settings or another device. Do not delete this device's copy,
          // and do not upload it again unasked.
          stop()
          await status("unavailable", issue: "cloudDataDeleted", message: "the data in iCloud was deleted")
        }
      }

    case .fetchedRecordZoneChanges(let changes):
      let records = changes.modifications.compactMap { encode($0.record) }
      if !records.isEmpty {
        _ = await callDart("fetched", ["records": records])
      }

    case .sentRecordZoneChanges(let sent):
      let saved = sent.savedRecords.compactMap { encode($0) }
      if !saved.isEmpty {
        _ = await callDart("saved", ["records": saved])
      }
      var refused: [[String: Any]] = []
      for failure in sent.failedRecordSaves {
        let id = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
          // Another device saved first. Dart merges the server's copy, which marks the record
          // unsent again if this device still holds something the server does not.
          if let server = failure.error.serverRecord, let encoded = encode(server) {
            refused.append(encoded)
          }
        case .zoneNotFound:
          syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
          syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .unknownItem:
          // The record vanished from the server; save it again as a new one.
          forgetSystemFields.insert(id.recordName)
          syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .quotaExceeded:
          await status("unavailable", issue: "quotaExceeded", message: failure.error.localizedDescription)
        default:
          await status("unavailable", issue: "other", message: failure.error.localizedDescription)
        }
      }
      if !refused.isEmpty {
        _ = await callDart("refused", ["records": refused])
      }

    case .willFetchChanges, .willSendChanges:
      await status("syncing")

    case .didFetchChanges, .didSendChanges:
      if syncEngine.state.pendingRecordZoneChanges.isEmpty && syncEngine.state.pendingDatabaseChanges.isEmpty {
        await status("upToDate")
      }

    default:
      break
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
    let names: [String] = pending.compactMap {
      if case .saveRecord(let id) = $0 { return id.recordName }
      return nil
    }
    guard !names.isEmpty else { return nil }
    let reply = await callDart("outgoing", ["names": names]) as? [[String: Any]] ?? []
    var records: [String: CKRecord] = [:]
    for item in reply {
      guard let name = item["name"] as? String,
            let payload = (item["payload"] as? FlutterStandardTypedData)?.data else { continue }
      let system = forgetSystemFields.contains(name) ? nil : (item["system"] as? FlutterStandardTypedData)?.data
      forgetSystemFields.remove(name)
      let record = system.flatMap(Self.record(fromSystemFields:))
        ?? CKRecord(recordType: Self.recordType, recordID: recordID(name))
      record.encryptedValues[Self.stateField] = payload
      records[name] = record
    }
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { records[$0.recordName] }
  }

  // MARK: Translation

  private var forgetSystemFields: Set<String> = []

  private func recordID(_ name: String) -> CKRecord.ID {
    CKRecord.ID(recordName: name, zoneID: zoneID)
  }

  /// A record as Dart takes it: its name, its decrypted state, and its system fields (the change
  /// tag a later save must match), archived.
  private func encode(_ record: CKRecord) -> [String: Any]? {
    guard let payload = record.encryptedValues[Self.stateField] as? Data else { return nil }
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return [
      "name": record.recordID.recordName,
      "payload": FlutterStandardTypedData(bytes: payload),
      "system": FlutterStandardTypedData(bytes: archiver.encodedData),
    ]
  }

  private static func record(fromSystemFields data: Data) -> CKRecord? {
    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    unarchiver.requiresSecureCoding = true
    defer { unarchiver.finishDecoding() }
    return CKRecord(coder: unarchiver)
  }

  private func status(_ state: String, issue: String? = nil, message: String? = nil) async {
    var arguments: [String: Any] = ["state": state]
    if let issue { arguments["issue"] = issue }
    if let message { arguments["message"] = message }
    _ = await callDart("status", arguments)
  }

  /// Calls Dart on the platform thread and waits for its answer.
  private func callDart(_ method: String, _ arguments: Any?) async -> Any? {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        self.channel.invokeMethod(method, arguments: arguments) { continuation.resume(returning: $0) }
      }
    }
  }
}
