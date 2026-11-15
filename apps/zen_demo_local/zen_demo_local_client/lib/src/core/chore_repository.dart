import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';

/// The chore list: one collection in the device's store.
final class ChoreRepository {
  static const String collectionName = 'chores';

  final ZenCollection<Chore> collection;

  ChoreRepository(ZenStore store) : collection = store.collection(collectionName, Chore.fromBuffer);

  /// Every live chore, open ones first, then by title.
  List<Chore> list() {
    final chores = [...(collection.list().dataOrNull ?? const <Chore>[])];
    chores.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return chores;
  }

  Chore? get(String id) => collection.get(id).dataOrNull;

  Future<ZenResult<Chore>> save(Chore chore) => collection.put(chore.id, chore);

  Future<ZenResult<Chore>> remove(String id) => collection.delete(id);

  /// Applies to the chore as it is *now* only what the person changed between [before] (what the
  /// form showed when it opened) and [after] (what they left), and saves that.
  ///
  /// `ZenCollection.put` counts every field that differs from the stored record as this device's
  /// edit. Saving [after] whole would therefore send back, as a fresh edit, a field another device
  /// changed while the form was open: a silent last-writer-wins. Starting from the current record
  /// leaves such a field alone, and a field both devices really changed is the conflict it should be.
  ///
  /// Fails with [ZenNotFoundError] when the chore was deleted meanwhile, rather than bringing it
  /// back.
  Future<ZenResult<Chore>> edit(Chore before, Chore after) {
    final current = get(before.id);
    if (current == null) {
      return Future.value(ZenResult.err(ZenNotFoundError('Chore ${before.id} is gone.')));
    }
    final merged = current.deepCopy();
    if (after.title != before.title) merged.title = after.title;
    if (after.note != before.note) merged.note = after.note;
    if (after.done != before.done) merged.done = after.done;
    if (after.priority != before.priority) merged.priority = after.priority;
    return save(merged);
  }
}
