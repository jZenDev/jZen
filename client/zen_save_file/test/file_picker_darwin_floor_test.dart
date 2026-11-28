import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first `file_picker_darwin` whose iOS `saveFile` deletes the temporary file it exports.
const _floor = (2, 5, 2);

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Fails unless the three numbers [match] captured are [_floor] or newer.
void _expectAtLeastFloor(RegExpMatch match, String what) {
  final (major, minor, patch) = (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  final (floorMajor, floorMinor, floorPatch) = _floor;
  final atLeastFloor =
      major > floorMajor ||
      (major == floorMajor && (minor > floorMinor || (minor == floorMinor && patch >= floorPatch)));
  expect(
    atLeastFloor,
    isTrue,
    reason: '$what $major.$minor.$patch admits a release that leaves the iOS copy',
  );
}

// Older releases leave a plaintext copy of the saved bytes in the app's temporary directory, and no
// Dart test can see that: it happens in the plugin's Swift. What holds it back is the version, which
// nothing else in this package would miss — `file_picker` itself still admits the older releases,
// and no code here imports the package.
void main() {
  // The constraint is what a consumer of this package inherits.
  test('file_picker_darwin cannot resolve below the release that deletes the iOS export', () {
    // A comment at column zero does not end the section.
    final dependencies = RegExp(
      r'^dependencies:\n((?:(?:[ \t#].*)?\n)*)',
      multiLine: true,
    ).firstMatch(_read('pubspec.yaml'));
    expect(dependencies, isNotNull, reason: 'pubspec.yaml has no dependencies section');

    final constraint = RegExp(
      r'''^  file_picker_darwin:[ \t]*["']?(?:\^|>=)[ \t]*(\d+)\.(\d+)\.(\d+)(?![\d.+-])''',
      multiLine: true,
    ).firstMatch(dependencies!.group(1)!);
    expect(
      constraint,
      isNotNull,
      reason: 'file_picker_darwin must be a direct dependency with a lower bound',
    );
    _expectAtLeastFloor(constraint!, 'the lower bound');
  });

  // A `dependency_overrides` entry replaces the constraint, so the version this workspace actually
  // builds with is checked too.
  test('the workspace lock resolves no older file_picker_darwin', () {
    final locked = RegExp(
      r'^  file_picker_darwin:\n(?:    .*\n)*?    version: "(\d+)\.(\d+)\.(\d+)(?:\+[\w.]+)?"$',
      multiLine: true,
    ).firstMatch(_read('../pubspec.lock'));
    expect(locked, isNotNull, reason: '../pubspec.lock resolves no released file_picker_darwin');
    _expectAtLeastFloor(locked!, 'the locked version');
  });
}
