import 'dart:io';

import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

/// Several real stores, one per device name, syncing through one folder — for conflicts that the
/// two-device `ConflictFixture` cannot make: many records at once, and a third device.
///
/// Api stands in for an application's message (name = field 1, version = field 4).
final class DevicesFixture {
  final Directory root;
  final Map<String, ZenStore> stores;
  final List<ZenFolderCloud> clouds;

  DevicesFixture._(this.root, this.stores, this.clouds);

  ZenStore operator [](String device) => stores[device]!;

  ZenCollection<Api> items(String device) => this[device].collection('items', Api.fromBuffer);

  /// File I/O never completes under a widget test's fake clock, so callers run this inside
  /// `tester.runAsync`.
  static Future<DevicesFixture> create(List<String> deviceNames) async {
    final root = await Directory.systemTemp.createTemp('zen_ui_store_devices');
    final stores = <String, ZenStore>{};
    final clouds = <ZenFolderCloud>[];
    for (final name in deviceNames) {
      final store = (await ZenStore.open(
        Directory('${root.path}/${name.replaceAll(' ', '_')}'),
        deviceName: name,
        key: List.filled(32, 3),
        now: () => DateTime.utc(2026, 10, 1, 9 + deviceNames.indexOf(name)).millisecondsSinceEpoch,
      )).dataOrNull!;
      stores[name] = store;
      clouds.add(
        (await ZenFolderCloud.start(
          store,
          Directory('${root.path}/cloud'),
          pollEvery: null,
        )).dataOrNull!,
      );
    }
    return DevicesFixture._(root, stores, clouds);
  }

  Future<void> syncAll() async {
    for (var round = 0; round < 3; round++) {
      for (final cloud in clouds) {
        await cloud.syncNow();
      }
    }
  }

  /// Every record in [ids] exists on every device, with the version "base".
  Future<void> seed(Iterable<String> ids) async {
    final first = stores.keys.first;
    for (final id in ids) {
      await items(first).put(id, Api(name: 'Record $id', version: 'base'));
    }
    await syncAll();
  }

  /// [device] sets the version of record [id] to [version].
  Future<void> edit(String device, String id, String version) async =>
      items(device).put(id, Api(name: 'Record $id', version: version));

  ZenConflictSource<Api> source(String device) =>
      ZenConflictSource<Api>(collection: items(device), title: (value) => value.name);

  Future<void> dispose() async {
    for (final cloud in clouds) {
      await cloud.stop();
    }
    await root.delete(recursive: true);
  }
}
