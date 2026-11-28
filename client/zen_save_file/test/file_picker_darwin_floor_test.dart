import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first `file_picker_darwin` whose iOS `saveFile` deletes the temporary file it exports.
const _floor = (2, 5, 2);

void main() {
  // Older releases leave a plaintext copy of the saved bytes in the app's temporary directory, and
  // no Dart test can see that: it happens in the plugin's Swift. What holds it back is the version
  // constraint, which nothing else in this package would miss — `file_picker` itself still admits
  // the older releases, and no code here imports the package.
  test('file_picker_darwin cannot resolve below the release that deletes the iOS export', () {
    final dependencies = RegExp(
      r'^dependencies:\n((?:(?:[ \t].*)?\n)*)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync().replaceAll('\r\n', '\n'));
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

    final (major, minor, patch) = (
      int.parse(constraint!.group(1)!),
      int.parse(constraint.group(2)!),
      int.parse(constraint.group(3)!),
    );
    final (floorMajor, floorMinor, floorPatch) = _floor;
    final atLeastFloor =
        major > floorMajor ||
        (major == floorMajor &&
            (minor > floorMinor || (minor == floorMinor && patch >= floorPatch)));
    expect(
      atLeastFloor,
      isTrue,
      reason: 'the lower bound $major.$minor.$patch admits a release that leaves the iOS copy',
    );
  });
}
