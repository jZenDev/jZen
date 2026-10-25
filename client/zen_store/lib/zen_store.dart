/// jZen Store - encrypted, offline-first persistence for a light (serverless) jZen application.
///
/// - [ZenStore]: proto messages by collection and id, AES-256-GCM on disk, readable offline
/// - [ZenCollection]: a typed view of one collection, answering with `ZenResult`
/// - [ZenConflict]: edits that cannot both be kept, waiting for a person to choose
/// - [ZenSyncTransport]: what carries records between devices (`zen_store_cloudkit` in release)
/// - [ZenFolderCloud]: a CloudKit stand-in in a folder, for development without an Apple account
///
/// See docs/architecture/DECISIONS.md ADR-065.
library;

export 'src/zen_collection.dart' show ZenCollection;
export 'src/zen_conflict.dart';
export 'src/zen_folder_cloud.dart';
export 'src/zen_storage_error.dart';
export 'src/zen_store.dart';
export 'src/zen_sync_report.dart';
export 'src/zen_sync_transport.dart';
