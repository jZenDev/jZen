import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'package:zen_demo_local_client/generated/zen_demo_local/v1/chore.pb.dart';
import 'package:zen_demo_local_client/src/core/chore_repository.dart';

void main() {
  late Directory root;
  late ZenStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zen_demo_local_repo');
    store = (await ZenStore.open(root, deviceName: 'Test', key: List.filled(32, 1))).dataOrNull!;
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('open chores come first, then by title regardless of case', () async {
    final chores = ChoreRepository(store);
    await chores.save(Chore(id: 'a', title: 'zebra', done: true));
    await chores.save(Chore(id: 'b', title: 'banana'));
    await chores.save(Chore(id: 'c', title: 'Apple'));

    expect(chores.list().map((c) => c.title), ['Apple', 'banana', 'zebra']);
  });

  test('a removed chore is gone from the list', () async {
    final chores = ChoreRepository(store);
    await chores.save(Chore(id: 'a', title: 'Dishes'));
    await chores.remove('a');

    expect(chores.list(), isEmpty);
    expect(chores.get('a'), isNull);
  });

  test('an edit applies only what changed to the chore as it is now', () async {
    final chores = ChoreRepository(store);
    final opened = Chore(id: 'a', title: 'Dishes', note: 'old');
    await chores.save(opened);
    // Meanwhile (a sync) the priority changed in the store.
    await chores.save(opened.deepCopy()..priority = Priority.PRIORITY_HIGH);

    await chores.edit(opened, opened.deepCopy()..note = 'new');

    final now = chores.get('a')!;
    expect(now.note, 'new');
    expect(now.priority, Priority.PRIORITY_HIGH);
  });

  test('an edit of a chore that is gone fails instead of making it again', () async {
    final chores = ChoreRepository(store);
    final opened = Chore(id: 'a', title: 'Dishes');
    await chores.save(opened);
    await chores.remove('a');

    final result = await chores.edit(opened, opened.deepCopy()..note = 'x');

    expect(result.errorOrNull, isA<ZenNotFoundError>());
    expect(chores.get('a'), isNull);
  });
}
