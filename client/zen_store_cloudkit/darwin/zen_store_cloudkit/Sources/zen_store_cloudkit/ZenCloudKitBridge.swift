import CloudKit
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import Foundation
import ZenDeliveryLedger
import ZenRecordNames

/// `CKSyncEngine` against the user's private database, with the store on the Dart side as the
/// source of truth.
///
/// Each store record is one CloudKit record in one custom zone, named by an HMAC of the store's
/// `<collection>:<id>` (`ZenRecordNames`, ADR-083), so Apple sees neither collections nor ids. Its
/// state and its plain name are fields in `encryptedValues`: CloudKit encrypts them on the device
/// with keys in the user's iCloud Keychain, so Apple holds only ciphertext. The engine owns the sync loop —
/// what to send, batching, retries, push-triggered fetches, change tokens — and this class only
/// translates: it asks Dart for payloads to send, hands Dart what was fetched, confirms saves, and
/// returns the server's copy when a save was refused because it changed, for Dart to merge.
///
/// Every call into Dart is awaited before the engine moves on, so the engine's state, which holds
/// the change token, reaches Dart after the changes before it. Dart writes the state only once all
/// of those are on disk. A change Dart did not take at all ends the saving of state here
/// (`ZenDeliveryLedger`, ADR-088), so CloudKit delivers it again.
final class ZenCloudKitBridge: CKSyncEngineDelegate, @unchecked Sendable {
  private static let recordType = "ZenRecord"
  private static let stateField = "state"
  private static let nameField = "name"
  /// Marks a saved engine state as belonging to the hashed-name zone; one without it is from the
  /// plain-name zone this version replaces.
  private static let stateMarker = Data("zen-v2\n".utf8)

  private let channel: FlutterMethodChannel
  private let container: CKContainer
  private let zoneID: CKRecordZone.ID
  private let legacyZoneID: CKRecordZone.ID
  /// Holds the one record that says "erased everywhere". It is a zone of its own because the data
  /// zone is deleted by an erase, and a device that was off must still find out afterwards: with
  /// only the data zone gone it could not tell an erase from a deletion in iCloud Settings.
  private let markerZoneID: CKRecordZone.ID
  private let markerRecordID: CKRecord.ID
  private static let markerType = "ZenErased"
  private var erasing = false
  private let containerId: String?
  private let initialState: CKSyncEngine.State.Serialization?
  private let hadLegacyState: Bool
  private var names: ZenRecordNames?
  /// Hashed record name to the store's name, for the records this run has been told about.
  private var plainNames: [String: String] = [:]
  private var engine: CKSyncEngine?
  private var stopped = false
  private var ledger = ZenDeliveryLedger()
  /// Set once the app has stopped this sync. Read and written on the platform thread only.
  private var detached = false

  init(channel: FlutterMethodChannel, containerId: String?, zone: String, state: Data?) {
    self.channel = channel
    container = containerId.map { CKContainer(identifier: $0) } ?? CKContainer.default()
    self.containerId = containerId
    // A new zone, not a rename in place: records already in the old zone carry plain names.
    zoneID = CKRecordZone.ID(zoneName: "\(zone)_v2", ownerName: CKCurrentUserDefaultName)
    legacyZoneID = CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
    markerZoneID = CKRecordZone.ID(zoneName: "\(zone)_erased", ownerName: CKCurrentUserDefaultName)
    markerRecordID = CKRecord.ID(recordName: "erased", zoneID: markerZoneID)
    hadLegacyState = state.map { !$0.starts(with: Self.stateMarker) } ?? false
    initialState = state
      .flatMap { $0.starts(with: Self.stateMarker) ? $0.dropFirst(Self.stateMarker.count) : nil }
      .flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: Data($0)) }
  }

  func start() async {
    do {
      names = try ZenRecordNames(key: ZenRecordNames.loadKey(account: containerId ?? "default"))
    } catch {
      // Without the key no record can be named, and a plain name must never be the fallback.
      await status("unavailable", issue: "other", message: error.localizedDescription)
      return
    }
    do {
      let account = try await container.accountStatus()
      if account != .available {
        await status("unavailable", issue: "noAccount", message: "iCloud account status: \(account.rawValue)")
      }
    } catch {
      await status("unavailable", issue: "other", message: error.localizedDescription)
    }
    // An erased store must not start a zone again: say so to Dart and stay stopped.
    if await markerExists() {
      stop()
      await deliver("erased", nil)
      return
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
    if hadLegacyState {
      // This device used the plain-name zone. Send everything again under hashed names, then
      // remove the old zone so Apple no longer holds the names.
      await deliver("resetCloud", nil)
      engine.state.add(pendingDatabaseChanges: [.deleteZone(legacyZoneID)])
    }
    self.engine = engine
  }

  func changed(_ names: [String]) {
    guard let engine, !stopped else { return }
    engine.state.add(pendingRecordZoneChanges: names.compactMap { name in recordID(name).map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) } })
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

  /// Erases the person's data in iCloud: leaves the marker for devices that were off, then deletes
  /// the data zone (and the plain-name zone an older version used). Returns the error's
  /// description, or nil once the engine has sent it all.
  func eraseEverywhere() async -> String? {
    guard let engine, !stopped else { return "sync was not started" }
    erasing = true
    // Nothing waiting for the data zone is worth sending now.
    let doomed = engine.state.pendingRecordZoneChanges.filter {
      if case .saveRecord(let id) = $0 { return id.zoneID == zoneID }
      return false
    }
    engine.state.remove(pendingRecordZoneChanges: doomed)
    engine.state.add(pendingDatabaseChanges: [
      .saveZone(CKRecordZone(zoneID: markerZoneID)),
      .deleteZone(zoneID),
      .deleteZone(legacyZoneID),
    ])
    engine.state.add(pendingRecordZoneChanges: [.saveRecord(markerRecordID)])
    do {
      try await engine.sendChanges()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  /// Whether the erased marker is in iCloud. A failure to ask answers false: the engine's own
  /// fetch finds the marker later, and asking again costs nothing.
  private func markerExists() async -> Bool {
    do {
      _ = try await container.privateCloudDatabase.record(for: markerRecordID)
      return true
    } catch {
      return false
    }
  }

  func stop() {
    stopped = true
    engine = nil
  }

  /// Stops for the app, on the platform thread: this bridge calls Dart no more. A late event of
  /// its engine would reach whatever sync started next, with a state that may be past changes the
  /// store was never given.
  func detach() {
    detached = true
    stop()
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case .stateUpdate(let update):
      guard ledger.maySaveState else { break }
      if let data = try? JSONEncoder().encode(update.stateSerialization) {
        _ = await callDart("state", ["state": FlutterStandardTypedData(bytes: Self.stateMarker + data)])
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
      for deletion in changes.deletions where deletion.zoneID == zoneID && !erasing {
        // Another device erased everything: its marker says so, and this device erases too.
        if await markerExists() {
          stop()
          await deliver("erased", nil)
          continue
        }
        switch deletion.reason {
        case .encryptedDataReset:
          // The user's iCloud Keychain was reset: the old ciphertext is unreadable by anyone.
          // Start the zone again and send everything this device holds.
          await deliver("resetCloud", nil)
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
      if changes.modifications.contains(where: { $0.record.recordID.zoneID == markerZoneID }) && !erasing {
        stop()
        await deliver("erased", nil)
        break
      }
      var records: [[String: Any]] = []
      var unreadable = false
      for modification in changes.modifications {
        if let encoded = encode(modification.record) {
          records.append(encoded)
        } else if modification.record.recordID.zoneID == zoneID {
          unreadable = true
        }
      }
      if !records.isEmpty {
        await deliver("fetched", ["records": records])
      }
      if unreadable {
        ledger.lose()
        await status(
          "unavailable", issue: "unreadableRecords",
          message: "a record in iCloud could not be read; it is fetched again at the next launch")
      }

    case .sentRecordZoneChanges(let sent):
      let saved = sent.savedRecords.compactMap { encode($0) }
      if !saved.isEmpty {
        await deliver("saved", ["records": saved])
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
          // Not a reason to make the zone again when it is gone because everything was erased.
          if erasing { break }
          if await markerExists() {
            stop()
            await deliver("erased", nil)
            break
          }
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
        await deliver("refused", ["records": refused])
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
    // Names the store does not know in this run (pending from an earlier launch, before Dart
    // listed what is unsent) are skipped; the store names them again at start.
    let names: [String] = pending.compactMap {
      if case .saveRecord(let id) = $0 { return plainNames[id.recordName] }
      return nil
    }
    var records: [String: CKRecord] = [:]
    let sendsMarker = pending.contains {
      if case .saveRecord(let id) = $0 { return id == markerRecordID }
      return false
    }
    if sendsMarker {
      records[markerRecordID.recordName] = CKRecord(recordType: Self.markerType, recordID: markerRecordID)
    }
    guard !names.isEmpty || sendsMarker else { return nil }
    let reply = names.isEmpty ? [] : (await callDart("outgoing", ["names": names]) as? [[String: Any]] ?? [])
    for item in reply {
      guard let name = item["name"] as? String,
            let payload = (item["payload"] as? FlutterStandardTypedData)?.data else { continue }
      guard let id = recordID(name) else { continue }
      let system = forgetSystemFields.contains(id.recordName) ? nil : (item["system"] as? FlutterStandardTypedData)?.data
      forgetSystemFields.remove(id.recordName)
      let record = system.flatMap(Self.record(fromSystemFields:))
        ?? CKRecord(recordType: Self.recordType, recordID: id)
      record.encryptedValues[Self.stateField] = payload
      record.encryptedValues[Self.nameField] = name
      records[id.recordName] = record
    }
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { records[$0.recordName] }
  }

  // MARK: Translation

  private var forgetSystemFields: Set<String> = []

  /// The record ID for the store's [name], remembering which name it stands for.
  private func recordID(_ name: String) -> CKRecord.ID? {
    guard let names else { return nil }
    let hashed = names.hashed(name)
    plainNames[hashed] = name
    return CKRecord.ID(recordName: hashed, zoneID: zoneID)
  }

  /// A record as Dart takes it: its name, its decrypted state, and its system fields (the change
  /// tag a later save must match), archived.
  private func encode(_ record: CKRecord) -> [String: Any]? {
    guard let payload = record.encryptedValues[Self.stateField] as? Data,
          let name = record.encryptedValues[Self.nameField] as? String else { return nil }
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return [
      "name": name,
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
    guard ledger.mayReport(state) else { return }
    var arguments: [String: Any] = ["state": state]
    if let issue { arguments["issue"] = issue }
    if let message { arguments["message"] = message }
    _ = await callDart("status", arguments)
  }

  /// Hands Dart a change for the store. Unless Dart takes it, no later state of this engine is
  /// saved, and the status says why.
  private func deliver(_ method: String, _ arguments: Any?) async {
    let reply = await callDart(method, arguments)
    if !ledger.took(reply) {
      let cause = (reply as? FlutterError)?.message ?? "no answer"
      await status(
        "unavailable", issue: "other",
        message: "\(method) did not reach the store (\(cause)); it is fetched again at the next launch")
    }
  }

  /// Calls Dart on the platform thread and waits for its answer.
  private func callDart(_ method: String, _ arguments: Any?) async -> Any? {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        guard !self.detached else {
          continuation.resume(returning: nil)
          return
        }
        self.channel.invokeMethod(method, arguments: arguments) { continuation.resume(returning: $0) }
      }
    }
  }
}
