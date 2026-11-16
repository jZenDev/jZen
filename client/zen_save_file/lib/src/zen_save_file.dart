import 'dart:typed_data';

import 'zen_save_file_error.dart';
import 'zen_save_file_port.dart';

/// Offers [bytes] to the person as a file called [name], through the platform's own save
/// surface: the save or share-to-Files sheet on iOS and Android, the save panel on desktop, a
/// download on the web.
///
/// Returns true once the file was written, and false when the person cancelled — which writes
/// nothing and is not an error. A write the platform refused (no space, a destination that cannot
/// be written, a name it rejects) throws a [ZenSaveFileError], so a failure is never mistaken for
/// a cancel and an export is never reported as saved when it was not.
///
/// [name] is a file name with no folder in it: the person chooses where it goes. [mimeType] lets
/// the platform label and open the file correctly.
///
/// [port] is the seam under the plugin, for a suite that stands in for the platform; an
/// application never passes it.
Future<bool> zenSaveFile(
  String name,
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
  ZenSaveFilePort? port,
}) async {
  if (name.trim().isEmpty || name.contains('/') || name.contains(r'\') || name.contains('\x00')) {
    throw ZenSaveFileError('"$name" is not a file name: no folder, not empty.');
  }
  try {
    return await (port ?? const ZenPluginSaveFilePort()).save(name, bytes, mimeType);
  } on ZenSaveFileError {
    rethrow;
  } on Object catch (e, stack) {
    Error.throwWithStackTrace(ZenSaveFileError('Cannot save $name: $e'), stack);
  }
}
