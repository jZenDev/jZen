import 'package:meta/meta.dart';

import 'zen_conflict_source.dart';

/// Every conflict between the same two devices that one choice can settle: "keep [first]'s version
/// of all of them" or "keep [second]'s".
///
/// A sweep takes in only a conflict that is a plain disagreement between exactly these two
/// devices — one version from each, neither a delete, no third device. Anything else that involves
/// either device is [left]: a delete against an edit, a record a third device also changed, or one
/// with several versions from one device is a different question that one choice for the others
/// does not answer, so it is named to the person and never settled here.
@internal
final class ZenConflictSweep {
  /// One device of the pair, as `(id, name)`; [first] is this device when it is one of the two.
  final (String, String) first;

  /// The other device of the pair, as `(id, name)`.
  final (String, String) second;

  /// The conflicts a choice settles, at least two.
  final List<ZenConflictView> included;

  /// The conflicts that involve either device and are not [included].
  final List<ZenConflictView> left;

  /// The id of the device the screen runs on.
  final String thisDevice;

  const ZenConflictSweep._(this.first, this.second, this.included, this.left, this.thisDevice);

  /// The sweeps [conflicts] allow: one per pair of devices that disagree on at least two records.
  /// [thisDevice] is the id of the device running the screen, listed first in its pairs.
  static List<ZenConflictSweep> of(List<ZenConflictView> conflicts, {required String thisDevice}) {
    final pairs = <String, List<ZenConflictView>>{};
    final names = <String, String>{};
    for (final conflict in conflicts) {
      for (final side in conflict.sides) {
        names[side.device] = side.deviceName;
      }
      if (_pair(conflict) case final pair?) (pairs[pair.join('\u0000')] ??= []).add(conflict);
    }
    final sweeps = <ZenConflictSweep>[];
    for (final MapEntry(key: key, value: included) in pairs.entries) {
      if (included.length < 2) continue;
      var devices = key.split('\u0000');
      if (devices.last == thisDevice) devices = devices.reversed.toList();
      final left = [
        for (final conflict in conflicts)
          if (!included.contains(conflict) &&
              conflict.sides.any((side) => devices.contains(side.device)))
            conflict,
      ];
      sweeps.add(
        ZenConflictSweep._(
          (devices[0], names[devices[0]]!),
          (devices[1], names[devices[1]]!),
          included,
          left,
          thisDevice,
        ),
      );
    }
    // The pairs with the most records first, so the largest saving of taps is the first row.
    return sweeps..sort((a, b) => b.included.length.compareTo(a.included.length));
  }

  /// The two device ids, sorted, when [conflict] is a plain disagreement between exactly two:
  /// two sides, from two different devices, so that "this device's version" names one thing.
  static List<String>? _pair(ZenConflictView conflict) {
    if (conflict.sides.length != 2 || conflict.sides.any((side) => side.isDelete)) return null;
    final devices = [for (final side in conflict.sides) side.device]..sort();
    return devices[0] == devices[1] ? null : devices;
  }

  /// Whether [device] is this device.
  bool isThisDevice(String device) => device == thisDevice;

  /// Settles every included conflict with [device]'s version, one record after another, stopping
  /// at the first write that fails. A record the store no longer holds as it was shown — a sync
  /// changed it since — is skipped, because the person chose between versions that are not all
  /// there is any more.
  Future<ZenSweepOutcome> keep(String device) async {
    assert(device == first.$1 || device == second.$1);
    var settled = 0;
    var changed = 0;
    var failed = false;
    for (final conflict in included) {
      if (!conflict.isCurrent()) {
        changed++;
        continue;
      }
      final side = conflict.sides.singleWhere((side) => side.device == device);
      final result = await side.keep();
      if (!result.isSuccess) {
        failed = true;
        break;
      }
      settled++;
    }
    return ZenSweepOutcome(
      settled: settled,
      total: included.length,
      changed: changed,
      failed: failed,
    );
  }
}

/// What [ZenConflictSweep.keep] did.
@internal
@immutable
final class ZenSweepOutcome {
  /// How many records were settled.
  final int settled;

  /// How many the sweep set out to settle.
  final int total;

  /// How many were skipped because they changed after they were shown.
  final int changed;

  /// Whether a write failed, which ended the sweep.
  final bool failed;

  const ZenSweepOutcome({
    required this.settled,
    required this.total,
    required this.changed,
    required this.failed,
  });

  /// Whether every record was settled.
  bool get isComplete => settled == total;
}
