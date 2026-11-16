import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The one platform operation behind [zenSaveFile], so a suite can stand in for the plugin and
/// check the capability's rules without a device.
abstract interface class ZenSaveFilePort {
  /// Shows the platform's save surface for [bytes] named [name]. True once written, false when
  /// the person cancelled; throws when the platform refused the write.
  Future<bool> save(String name, Uint8List bytes, String mimeType);
}

/// The plugin-backed port: `file_picker`'s save sheet on iOS, Android, macOS, Windows and Linux,
/// and a download on the web. The plugin writes the bytes itself on every one of them, so the
/// application never writes a path of its own.
final class ZenPluginSaveFilePort implements ZenSaveFilePort {
  /// Creates the port.
  const ZenPluginSaveFilePort();

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeType);
    return saved != null;
  }
}
