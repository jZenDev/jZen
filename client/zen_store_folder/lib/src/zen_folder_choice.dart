import 'package:meta/meta.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

/// A folder the person chose: how to reach it, and the text to keep so it can be reached again.
@immutable
final class ZenFolderChoice {
  /// A directory path on desktop, a `content://` tree uri on Android. Not secret; the app may keep
  /// it anywhere.
  final String reference;

  /// What to show the person: the path on desktop, the folder's name on Android.
  final String label;

  final ZenFolderAccess access;

  const ZenFolderChoice({required this.reference, required this.label, required this.access});
}
