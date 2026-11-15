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
}
