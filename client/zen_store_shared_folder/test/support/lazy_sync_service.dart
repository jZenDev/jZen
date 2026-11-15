import 'dart:io';
import 'dart:math';

/// A file sync service that behaves as badly as real ones do, between several replicas of one
/// folder (one per device).
///
/// A real service delivers files late, in any order, more than once, sometimes the old version of
/// a file after the new one, sometimes half a file, and when it believes two replicas changed one
/// file it writes a "conflicted copy" beside it. This one does all of that on demand, from a seeded
/// random so a failing run can be replayed. It never invents content: every byte it writes into a
/// replica was in some replica's file at some time.
final class LazySyncService {
  final List<Directory> replicas;

  /// The device id each replica belongs to: only a device's own directory is ever a source of
  /// truth, so a half-delivered file is never mistaken for a newer version.
  final List<String> owners;
  final Random _random;

  /// Chance, per file per round, that delivery is postponed to a later round.
  double delay;

  /// Chance that an older version of the file, seen in an earlier round, is delivered instead of
  /// the newest.
  double stale;

  /// Chance that only the first part of the file is delivered this round.
  double truncate;

  /// Chance that a conflicted copy of the file is written beside it, in each real-world naming
  /// style.
  double conflictedCopy;

  // path -> every distinct content seen for it, oldest first.
  final Map<String, List<List<int>>> _versions = {};

  LazySyncService(
    this.replicas,
    this.owners, {
    int seed = 1,
    this.delay = 0,
    this.stale = 0,
    this.truncate = 0,
    this.conflictedCopy = 0,
  }) : _random = Random(seed);

  /// Turns every fault off, as when a sync service has caught up.
  void behave() {
    delay = 0;
    stale = 0;
    truncate = 0;
    conflictedCopy = 0;
  }

  /// One delivery round: every replica's files are offered to every other replica.
  Future<void> pump() async {
    final files = <String>{};
    for (var i = 0; i < replicas.length; i++) {
      final replica = replicas[i];
      for (final file in _filesUnder(replica)) {
        final path = _relative(replica, file);
        if (_isRecordFile(path) && path.startsWith('${owners[i]}/')) {
          final content = await file.readAsBytes();
          final seen = _versions.putIfAbsent(path, () => []);
          if (seen.isEmpty || !_same(seen.last, content)) seen.add(content);
        }
        files.add(path);
      }
    }
    final order = files.toList()..shuffle(_random);
    for (final path in order) {
      final versions = _versions[path];
      // Not a record file (a conflicted copy, say): a real service would copy it too, and a test
      // does not need it to.
      if (versions == null) continue;
      for (var t = 0; t < replicas.length; t++) {
        final target = replicas[t];
        // A replica is the truth about its own files.
        if (path.startsWith('${owners[t]}/')) continue;
        if (_random.nextDouble() < delay) continue;
        var content = versions.last;
        if (versions.length > 1 && _random.nextDouble() < stale) {
          content = versions[_random.nextInt(versions.length - 1)];
        }
        final existing = File('${target.path}/$path');
        final whole = _random.nextDouble() >= truncate;
        if (whole && await existing.exists() && _same(await existing.readAsBytes(), content)) {
          continue;
        }
        await existing.parent.create(recursive: true);
        await existing.writeAsBytes(whole ? content : content.sublist(0, content.length ~/ 2));
        if (_random.nextDouble() < conflictedCopy) {
          final slash = path.lastIndexOf('/');
          final dir = path.substring(0, slash);
          final stem = path.substring(slash + 1, path.length - '.zen'.length);
          for (final name in [
            '$stem (conflicted copy 2026-11-14).zen',
            '$stem.sync-conflict-20261114-101010-ABCDEFG.zen',
            '$stem-DESKTOP-1.zen',
            '$stem (1).zen',
          ]) {
            await File('${target.path}/$dir/$name').writeAsBytes(content);
          }
        }
      }
    }
  }

  bool _isRecordFile(String path) => RegExp(r'^[0-9a-f]{32}/[0-9a-f]{64}\.zen$').hasMatch(path);

  Iterable<File> _filesUnder(Directory replica) =>
      replica.existsSync() ? replica.listSync(recursive: true).whereType<File>() : const [];

  String _relative(Directory replica, File file) =>
      file.path.substring(replica.path.length + 1).replaceAll(Platform.pathSeparator, '/');

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
