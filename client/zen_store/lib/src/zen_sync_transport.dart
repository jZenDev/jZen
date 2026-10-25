import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What carries a store's records to the user's other devices, and back.
///
/// The store does not sync by itself and never talks to a network. A transport takes the records
/// this device has changed (`ZenStore.unsent`, `ZenStore.outgoing`), delivers them, hands back what
/// other devices sent (`ZenStore.receive`) and confirms what arrived (`ZenStore.acknowledge`).
/// Every payload is the record's whole state, so the transport moves opaque bytes and the merge
/// stays the store's. `zen_store_cloudkit` is the transport a release build uses; [ZenFolderCloud]
/// stands in for it during development.
abstract interface class ZenSyncTransport {
  /// What the transport is doing, and why it stopped if it did.
  ZenSyncStatus get status;

  /// Each change of [status].
  Stream<ZenSyncStatus> get statusChanges;

  /// Sends what is waiting and fetches what is new, now rather than when the transport would next.
  Future<void> syncNow();

  /// Stops syncing. The store keeps working offline, and its unsent records stay unsent.
  Future<void> stop();
}

/// Where a transport stands.
enum ZenSyncState {
  /// Not started, or stopped.
  off,

  /// Sending or fetching.
  syncing,

  /// Nothing waiting to send, and nothing new known to fetch.
  upToDate,

  /// Cannot sync until something changes; [ZenSyncStatus.issue] says what.
  unavailable,
}

/// Why a transport cannot sync. Each is something a person can act on, which is why they are
/// named rather than folded into one message.
enum ZenSyncIssue {
  /// The device is not signed in to iCloud.
  noAccount,

  /// iCloud Keychain is off or was reset, so the encrypted records cannot be read here.
  keychainUnavailable,

  /// The device's iCloud account changed. Sync stops rather than send one person's data into
  /// another person's account.
  accountChanged,

  /// The records in iCloud were deleted (from Settings, or by another device). Sync stops rather
  /// than delete this device's copy too, or upload it again unasked.
  cloudDataDeleted,

  /// The iCloud storage is full.
  quotaExceeded,

  /// Something another device sent cannot be read here — usually a newer version of the app.
  unreadableRecords,

  /// Anything else; [ZenSyncStatus.message] says what.
  other,
}

/// A transport's [state], and the [issue] behind it when it is unavailable.
@immutable
final class ZenSyncStatus {
  /// Where the transport stands.
  final ZenSyncState state;

  /// Why it is unavailable; null otherwise.
  final ZenSyncIssue? issue;

  /// Detail for a log or a support request, not for showing as the explanation.
  final String? message;

  /// Creates a status.
  const ZenSyncStatus(this.state, {this.issue, this.message});

  /// Not started, or stopped.
  static const ZenSyncStatus off = ZenSyncStatus(ZenSyncState.off);

  @override
  bool operator ==(Object other) =>
      other is ZenSyncStatus &&
      other.state == state &&
      other.issue == issue &&
      other.message == message;

  @override
  int get hashCode => Object.hash(state, issue, message);

  @override
  String toString() =>
      'ZenSyncStatus(${state.name}${issue == null ? '' : ', ${issue!.name}'}'
      '${message == null ? '' : ': $message'})';
}

/// A record on its way out: its whole state, and what the transport last stored about it.
@immutable
final class ZenOutgoingRecord {
  /// The record's name, `<collection>:<id>`.
  final String name;

  /// The record's encoded state.
  final Uint8List payload;

  /// What the transport stored for this record the last time it saw it (CloudKit's system fields:
  /// the change tag a save must match), or null if it never has.
  final Uint8List? transportData;

  /// Creates an outgoing record.
  const ZenOutgoingRecord(this.name, this.payload, this.transportData);
}

/// A record that came from the transport: from another device, or the server's copy after a save
/// was refused because it had changed.
@immutable
final class ZenIncomingRecord {
  /// The record's name, `<collection>:<id>`.
  final String name;

  /// The record's encoded state as the transport holds it.
  final Uint8List payload;

  /// What the transport wants kept with the record for its next save of it.
  final Uint8List? transportData;

  /// Creates an incoming record.
  const ZenIncomingRecord(this.name, this.payload, this.transportData);
}

/// A save the transport completed: what it sent, and what it now holds about the record.
@immutable
final class ZenAcknowledgedRecord {
  /// The record's name.
  final String name;

  /// Exactly the payload that was saved. If the record changed since, it stays unsent.
  final Uint8List payload;

  /// What the transport wants kept with the record for its next save of it.
  final Uint8List? transportData;

  /// Creates an acknowledgement.
  const ZenAcknowledgedRecord(this.name, this.payload, this.transportData);
}
