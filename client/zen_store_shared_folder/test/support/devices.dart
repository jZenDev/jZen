import 'dart:io';
import 'dart:typed_data';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:test/test.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

/// Api stands in for an application's message: two independent text fields (name, version).
Api item(String name, [String? version]) => Api(name: name, version: version);

final List<int> storeKey = List.generate(32, (i) => i);
final List<int> syncKey = List.generate(32, (i) => 100 + i);
final List<int> otherSyncKey = List.generate(32, (i) => 200 + i);

/// Every write a device made through its access, as the paths it wrote.
final class RecordingAccess implements ZenFolderAccess {
  final ZenFolderAccess inner;
  final List<String> writes = [];
  RecordingAccess(this.inner);

  @override
  Future<ZenFolderState> check() => inner.check();
  @override
  Future<List<ZenFolderEntry>> list(String path) => inner.list(path);
  @override
  Future<Uint8List?> read(String path) => inner.read(path);
  @override
  Future<void> write(String path, Uint8List bytes) {
    writes.add(path);
    return inner.write(path, bytes);
  }

  @override
  Stream<void>? watch() => inner.watch();
}

/// One device: its store, the transport, and the folder replica it syncs through.
final class Device {
  final String name;
  final Directory storeDirectory;
  final Directory folder;
  final ZenStore store;
  final ZenSharedFolderSync sync;
  final RecordingAccess access;

  Device(this.name, this.storeDirectory, this.folder, this.store, this.sync, this.access);

  ZenCollection<Api> get items => store.collection('items', Api.fromBuffer);

  /// Syncs until nothing queued is left: a write also queues a sync of its own, which may run
  /// after one the test asked for.
  Future<void> syncUntilQuiet() async {
    await sync.syncNow();
    await sync.syncNow();
  }

  /// A snapshot of everything the device shows, conflicts included, to compare devices.
  String snapshot(Iterable<String> ids) => [
    for (final id in ids)
      '$id=${items.get(id).dataOrNull?.name}/${items.get(id).dataOrNull?.version}'
          '${items.conflictFor(id).dataOrNull == null ? '' : ' conflict:${(items.conflictFor(id).dataOrNull!.sides.map((s) => '${s.value?.name}/${s.value?.version}').toList()..sort()).join('|')}'}',
  ].join('\n');
}

/// Opens a device named [name] under [root], syncing through [folder] (default: the one every
/// device of the test shares, `root/folder`).
Future<Device> openDevice(
  Directory root,
  String name, {
  Directory? folder,
  List<int>? key,
  bool paired = true,
  List<int>? withSyncKey,
  ZenFolderAccess Function(Directory)? accessFor,
}) async {
  final storeDirectory = Directory('${root.path}/store_$name');
  final store = (await ZenStore.open(
    storeDirectory,
    deviceName: 'device $name',
    key: storeKey,
  )).dataOrNull!;
  final replica = folder ?? Directory('${root.path}/folder');
  // A chosen folder exists; tests that want it gone remove it.
  replica.createSync(recursive: true);
  final access = RecordingAccess(accessFor?.call(replica) ?? ZenDirectoryAccess(replica));
  final sync = (await ZenSharedFolderSync.start(
    store,
    access,
    syncKey: paired ? (withSyncKey ?? syncKey) : null,
    pollEvery: null,
    watch: false,
  )).dataOrNull!;
  addTearDown(sync.stop);
  addTearDown(store.close);
  return Device(name, storeDirectory, replica, store, sync, access);
}

/// Syncs every device, [rounds] times over, so that what one sends the others have fetched and
/// sent back.
Future<void> syncAll(List<Device> devices, {int rounds = 3}) async {
  for (var round = 0; round < rounds; round++) {
    for (final device in devices) {
      await device.sync.syncNow();
    }
  }
}

/// Every file under [folder], by path relative to it.
List<File> filesUnder(Directory folder) =>
    folder.listSync(recursive: true).whereType<File>().toList();
