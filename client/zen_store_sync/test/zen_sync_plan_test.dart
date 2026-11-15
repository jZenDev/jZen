import 'package:flutter_test/flutter_test.dart';
import 'package:zen_store_sync/zen_store_sync.dart';

const _refused = null;

void main() {
  // Every ZEN_PLATFORM the build can carry (and the ones it must not) against every ZEN_SYNC.
  // `null` is a refusal, with the reason checked below.
  const table = <String, Map<String, ZenSyncKind?>>{
    'ios': {
      '': ZenSyncKind.cloudKit,
      'folder': ZenSyncKind.folderCloud,
      'cloudkit': ZenSyncKind.cloudKit,
      'bogus': _refused,
    },
    'macos': {
      '': ZenSyncKind.cloudKit,
      'folder': ZenSyncKind.folderCloud,
      'cloudkit': ZenSyncKind.cloudKit,
      'bogus': _refused,
    },
    'android': {
      '': ZenSyncKind.sharedFolder,
      'folder': ZenSyncKind.folderCloud,
      'cloudkit': _refused,
      'bogus': _refused,
    },
    'windows': {
      '': ZenSyncKind.sharedFolder,
      'folder': ZenSyncKind.folderCloud,
      'cloudkit': _refused,
      'bogus': _refused,
    },
    'linux': {
      '': ZenSyncKind.sharedFolder,
      'folder': ZenSyncKind.folderCloud,
      'cloudkit': _refused,
      'bogus': _refused,
    },
    'web': {'': _refused, 'folder': _refused, 'cloudkit': _refused, 'bogus': _refused},
    '': {'': _refused, 'folder': _refused, 'cloudkit': _refused, 'bogus': _refused},
    'fuchsia': {'': _refused, 'folder': _refused, 'cloudkit': _refused, 'bogus': _refused},
  };

  for (final MapEntry(key: platform, value: row) in table.entries) {
    for (final MapEntry(key: sync, value: expected) in row.entries) {
      test("ZEN_PLATFORM='$platform' ZEN_SYNC='$sync' -> ${expected ?? 'refused'}", () {
        final plan = ZenSyncPlan(platform, sync);
        expect(plan.kind, expected);
        // Exactly one of the two is set: a plan is never both a transport and a refusal, and
        // never neither.
        expect(plan.refusal == null, expected != null);
      });
    }
  }

  test('a refusal says what to do', () {
    expect(const ZenSyncPlan('web', '').refusal, contains('ADR-073'));
    expect(const ZenSyncPlan('', '').refusal, contains('ZEN_PLATFORM'));
    expect(const ZenSyncPlan('linux', 'cloudkit').refusal, contains('shared folder'));
    expect(const ZenSyncPlan('ios', 'bogus').refusal, contains("'bogus'"));
  });

  test('the plan is a compile-time constant', () {
    // A const expression only compiles if the constructor is evaluated at build time, which is
    // what lets the tree-shaker drop the transports the platform never reaches.
    const plan = ZenSyncPlan('android', '');
    expect(plan.kind, ZenSyncKind.sharedFolder);
    expect(identical(plan, const ZenSyncPlan('android', '')), isTrue);
  });
}
