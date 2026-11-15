import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

import 'zen_folder_choice.dart';
import 'zen_saf_folder_access.dart';
import 'zen_saf_port.dart';

/// Lets the person choose the sync folder and rebuilds access to a folder chosen earlier.
///
/// The platform decides at compile time (`ZEN_PLATFORM`): the Storage Access Framework on Android,
/// the operating system's folder dialog elsewhere on desktop.
abstract final class ZenFolderPicker {
  /// Opens the folder dialog. Null when the person cancelled.
  static Future<ZenFolderChoice?> pick({ZenSafPort? port}) async {
    if (zenIsAndroid) {
      final picked = await (port ?? ZenPluginSafPort()).pickDirectory();
      if (picked == null) return null;
      return ZenFolderChoice(
        reference: picked.uri,
        label: picked.name,
        access: ZenSafFolderAccess(picked.uri, port: port),
      );
    }
    final path = await FilePicker.getDirectoryPath();
    return path == null ? null : restore(path);
  }

  /// The folder named by a [ZenFolderChoice.reference] kept from an earlier run.
  static ZenFolderChoice restore(String reference, {ZenSafPort? port}) {
    if (zenIsAndroid) {
      return ZenFolderChoice(
        reference: reference,
        label: Uri.decodeComponent(reference.split('/').last).split(':').last,
        access: ZenSafFolderAccess(reference, port: port),
      );
    }
    return ZenFolderChoice(
      reference: reference,
      label: reference,
      access: ZenDirectoryAccess(Directory(reference)),
    );
  }
}
