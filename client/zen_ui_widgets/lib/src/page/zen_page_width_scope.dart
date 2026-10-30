import 'package:flutter/widgets.dart';

/// Default body width for pages below this scope, including pages in nested navigators.
class ZenPageWidthScope extends InheritedWidget {
  /// Creates a page width configuration. The gutter is the space on each side.
  const ZenPageWidthScope({
    required this.maxWidth,
    required super.child,
    this.gutter = 16,
    super.key,
  }) : assert(maxWidth > 0 && maxWidth < double.infinity),
       assert(gutter >= 0 && gutter < double.infinity);

  /// Maximum width of a page body, excluding the gutter.
  final double maxWidth;

  /// Minimum horizontal space on each side.
  final double gutter;

  /// The nearest page width configuration, if any.
  static ZenPageWidthScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZenPageWidthScope>();

  @override
  bool updateShouldNotify(ZenPageWidthScope oldWidget) =>
      maxWidth != oldWidget.maxWidth || gutter != oldWidget.gutter;
}
