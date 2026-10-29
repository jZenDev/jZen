import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'detail_button_activation.dart';
import 'zen_detail_pane.dart';
import '../page/zen_page_route.dart';

/// The host width, in logical pixels, from which a detail opens beside its list. Narrower, it is a
/// full-screen push. A pane takes about two fifths of the width and at least 320, so this keeps
/// the list at 400 or more.
const double zenDetailMinWidth = 720;

const double _paneMinWidth = 320;
const double _paneMaxWidth = 420;
const double _paneFraction = 0.4;

/// Where a detail opened with `showZenDetail` appears: beside the list when the host is wide, and
/// as a full-screen push when it is narrow.
///
/// Wrap the list in it. The width that counts is the host's own, not the window's, so a list inside
/// a navigation sidebar is measured after the sidebar has taken its share.
///
/// | Platform | Wide host |
/// |---|---|
/// | iOS, macOS | an in-layout pane: the list narrows to make room, as in a split view or an inspector |
/// | Android, Windows, Linux, web | a side sheet over the list's trailing edge; the list stays operable |
///
/// The choice is on `zenIsApplePlatform`, a compile-time constant, so the idiom a build never uses
/// is tree-shaken. The width is a run-time decision, because a window can be resized.
///
/// The list keeps its state (its scroll position, its selection) while a detail opens and closes.
/// An icon button that synchronously opens a wide pane is highlighted until it closes or is
/// replaced; a narrow push does not highlight it. No caller state is required.
/// Narrowing the window under an open detail turns it into the full-screen push; widening it
/// again leaves a pushed page where it is.
class ZenDetailHost extends StatefulWidget {
  /// Creates a host around [child], the list.
  const ZenDetailHost({required this.child, super.key});

  /// The list the detail belongs to.
  final Widget child;

  @override
  State<ZenDetailHost> createState() => ZenDetailHostState();
}

/// The state of a [ZenDetailHost]; `showZenDetail` finds it.
class ZenDetailHostState extends State<ZenDetailHost> {
  _OpenDetail? _open;
  bool _wide = false;
  FocusNode? _opener;

  /// Opens [builder]'s page as the detail, from [caller]'s context. Use `showZenDetail`.
  Future<T?> show<T>(BuildContext caller, WidgetBuilder builder) {
    if (!_wide) return _push<T>(caller, builder);

    _finish(_open, null);
    _opener = FocusManager.instance.primaryFocus;
    final Completer<T?> completer = Completer<T?>();
    setState(() {
      _open = _OpenDetail(
        builder,
        (Object? result) => completer.complete(result as T?),
        activateDetailButton(),
      );
    });
    return completer.future;
  }

  Future<T?> _push<T>(BuildContext context, WidgetBuilder builder) {
    return Navigator.of(context).push<T>(ZenPageRoute<T>(builder: builder));
  }

  /// Ends [detail] with [result] if it is still the open one.
  void _finish(_OpenDetail? detail, Object? result) {
    if (detail == null || detail != _open) return;
    final FocusNode? opener = _opener;
    _opener = null;
    if (mounted) {
      setState(() => _open = null);
    } else {
      _open = null;
    }
    detail.deactivate?.call();
    detail.complete(result);
    if (opener != null && opener.context?.mounted == true && opener.canRequestFocus) {
      opener.requestFocus();
    }
  }

  /// The window narrowed under an open detail: carry it over to a full-screen push.
  void _demote() {
    final _OpenDetail? detail = _open;
    if (detail == null || !mounted) return;
    setState(() => _open = null);
    _opener = null;
    detail.deactivate?.call();
    Navigator.of(
      context,
    ).push<Object?>(ZenPageRoute<Object?>(builder: detail.builder)).then(detail.complete);
  }

  @override
  void dispose() {
    final _OpenDetail? detail = _open;
    _open = null;
    detail?.deactivate?.call();
    detail?.complete(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _wide = constraints.maxWidth >= zenDetailMinWidth;
        if (!_wide && _open != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _demote());
        }
        final _OpenDetail? detail = _wide ? _open : null;
        final Widget? pane = detail == null
            ? null
            : ZenDetailPane(
                key: ObjectKey(detail),
                builder: detail.builder,
                onClosed: (Object? result) => _finish(detail, result),
              );
        final double width = math.max(
          _paneMinWidth,
          math.min(_paneMaxWidth, constraints.maxWidth * _paneFraction),
        );
        return zenIsApplePlatform
            ? buildApplePanes(context, widget.child, pane, width)
            : buildMaterialPanes(context, widget.child, pane, width);
      },
    );
  }
}

class _OpenDetail {
  _OpenDetail(this.builder, this.complete, this.deactivate);

  final WidgetBuilder builder;
  final void Function(Object? result) complete;
  final VoidCallback? deactivate;
}

/// Apple: the pane is a column of the layout, and the list narrows. Exposed to the package's
/// tests, which cannot reach the branch the host platform did not compile.
Widget buildApplePanes(BuildContext context, Widget list, Widget? pane, double width) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final Duration duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);
  return Row(
    children: <Widget>[
      Expanded(child: list),
      AnimatedSwitcher(
        duration: duration,
        transitionBuilder: (Widget child, Animation<double> animation) => SizeTransition(
          sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          axis: Axis.horizontal,
          axisAlignment: 1,
          child: child,
        ),
        child: pane == null
            ? const SizedBox.shrink()
            : SizedBox(
                key: const ValueKey<String>('detail'),
                width: width + 1,
                child: Row(
                  children: <Widget>[
                    ColoredBox(
                      color: scheme.outlineVariant,
                      child: const SizedBox(width: 1, height: double.infinity),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: scheme.surface,
                        child: Material(type: MaterialType.transparency, child: pane),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ],
  );
}

/// Material: the pane is a side sheet over the list's trailing edge. See [buildApplePanes].
Widget buildMaterialPanes(BuildContext context, Widget list, Widget? pane, double width) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool still = MediaQuery.disableAnimationsOf(context);
  return Stack(
    children: <Widget>[
      Positioned.fill(child: list),
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: width,
        child: AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 200),
          transitionBuilder: (Widget child, Animation<double> animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
          child: pane == null
              ? const SizedBox.shrink()
              : Material(
                  key: const ValueKey<String>('detail'),
                  elevation: 3,
                  color: scheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: pane,
                ),
        ),
      ),
    ],
  );
}
