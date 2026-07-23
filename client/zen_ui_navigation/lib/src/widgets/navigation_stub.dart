import 'package:flutter/widgets.dart';

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';

/// Platform-specific navigation builder for stub
/// It renders a fallback skeleton
const PlatformNavigationBuilder buildPlatformNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) =>
    const Text(
        'Navigation not implemented for this platform'); // fallback skeleton
