import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

void main() {
  test('a desktop folder is restored from its path and reached with dart:io', () async {
    final dir = await Directory.systemTemp.createTemp('zen_folder_picker');
    addTearDown(() => dir.delete(recursive: true));
    final choice = ZenFolderPicker.restore(dir.path);
    expect(choice.reference, dir.path);
    expect(choice.label, dir.path);
    expect(await choice.access.check(), ZenFolderState.ready);
  });

  test('a folder that is gone is unreachable, not ready', () async {
    final choice = ZenFolderPicker.restore('${Directory.systemTemp.path}/zen_gone_folder');
    expect(await choice.access.check(), ZenFolderState.unreachable);
  });
}
