import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

/// Two real stores syncing through one folder, with a real conflict between them — the screens
/// are tested against what `zen_store` actually produces, not a hand-made conflict.
///
/// Api stands in for an application's message (name = field 1, version = field 4).
final class ConflictFixture {
  final Directory root;
  final ZenStore mac;
  final ZenStore phone;
  final ZenFolderCloud macCloud;
  final ZenFolderCloud phoneCloud;

  ConflictFixture._(this.root, this.mac, this.phone, this.macCloud, this.phoneCloud);

  ZenCollection<Api> items(ZenStore store) => store.collection('items', Api.fromBuffer);

  /// File I/O never completes under a widget test's fake clock, so callers run this inside
  /// `tester.runAsync`.
  static Future<ConflictFixture> create({bool deleteConflict = false}) async {
    final root = await Directory.systemTemp.createTemp('zen_ui_store_test');
    final cloudFolder = Directory('${root.path}/cloud');
    Future<(ZenStore, ZenFolderCloud)> open(String name, String deviceName, int at) async {
      final store = (await ZenStore.open(
        Directory('${root.path}/$name'),
        deviceName: deviceName,
        key: List.filled(32, 3),
        now: () => at,
      )).dataOrNull!;
      final cloud = (await ZenFolderCloud.start(store, cloudFolder, pollEvery: null)).dataOrNull!;
      return (store, cloud);
    }

    final (mac, macCloud) = await open(
      'mac',
      'Work Mac',
      DateTime.utc(2026, 10, 1, 9).millisecondsSinceEpoch,
    );
    final (phone, phoneCloud) = await open(
      'phone',
      'My iPhone',
      DateTime.utc(2026, 10, 2, 9).millisecondsSinceEpoch,
    );
    final fixture = ConflictFixture._(root, mac, phone, macCloud, phoneCloud);

    await fixture.items(mac).put('1', Api(name: 'Groceries', version: '10.00'));
    await fixture.syncAll();
    if (deleteConflict) {
      await fixture.items(mac).delete('1');
    } else {
      await fixture.items(mac).put('1', Api(name: 'Groceries', version: '12.50'));
    }
    await fixture.items(phone).put('1', Api(name: 'Groceries', version: '14.00'));
    await fixture.syncAll();
    return fixture;
  }

  Future<void> syncAll() async {
    for (var round = 0; round < 2; round++) {
      await macCloud.syncNow();
      await phoneCloud.syncNow();
    }
  }

  ZenConflictSource<Api> source(ZenStore store, {bool labelled = true}) => ZenConflictSource<Api>(
    collection: items(store),
    title: (value) => value.name,
    fieldLabel: labelled ? (field) => field == 4 ? 'Amount' : null : null,
  );

  Future<void> dispose() async {
    await macCloud.stop();
    await phoneCloud.stop();
    await root.delete(recursive: true);
  }
}

/// The app a light application builds around the screens.
Widget conflictApp({required Widget home, String locale = ZenLocales.en, ThemeData? theme}) =>
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: const [
        storeLocaleDelegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [for (final tag in ZenLocales.shipped) Locale(tag)],
      theme: theme,
      home: home,
    );
