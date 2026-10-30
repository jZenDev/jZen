import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus_ring.dart';
import 'slider_values.dart';

/// How a platform draws a range slider: the sizes and colours the shared body paints with.
///
/// The body is the same on every platform — what differs is the track, the thumb and the colours,
/// which is what [zenMaterialRangeSliderStyle] and [zenCupertinoRangeSliderStyle] supply.
@immutable
class ZenRangeSliderStyle {
  /// Creates a style.
  const ZenRangeSliderStyle({
    required this.trackHeight,
    required this.thumbDiameter,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.thumbBorderColor,
    required this.thumbShadow,
  });

  /// Thickness of the track.
  final double trackHeight;

  /// Diameter of each thumb.
  final double thumbDiameter;

  /// The part of the track between the thumbs.
  final Color activeColor;

  /// The rest of the track.
  final Color inactiveColor;

  /// The thumb's fill.
  final Color thumbColor;

  /// The thumb's outline; what keeps a light thumb visible on a light surface.
  final Color thumbBorderColor;

  /// The thumb's shadow, empty for a flat thumb.
  final List<BoxShadow> thumbShadow;
}

/// The Material look: a thin track, a small solid thumb in the theme's primary colour.
ZenRangeSliderStyle zenMaterialRangeSliderStyle(ThemeData theme) {
  final ColorScheme colors = theme.colorScheme;
  return ZenRangeSliderStyle(
    trackHeight: 4,
    thumbDiameter: 20,
    activeColor: colors.primary,
    // Material 3's own inactive track is a pale container colour, well under the 3:1 WCAG asks
    // of a graphic that shows a control's extent; the outline colour clears it.
    inactiveColor: colors.outline,
    thumbColor: colors.primary,
    thumbBorderColor: colors.primary,
    thumbShadow: const <BoxShadow>[],
  );
}

/// The Cupertino look: a thicker track and a larger white, shadowed thumb.
ZenRangeSliderStyle zenCupertinoRangeSliderStyle(ThemeData theme) {
  final ColorScheme colors = theme.colorScheme;
  return ZenRangeSliderStyle(
    trackHeight: 6,
    thumbDiameter: 28,
    activeColor: colors.primary,
    inactiveColor: colors.outline,
    thumbColor: Colors.white,
    thumbBorderColor: colors.outline,
    thumbShadow: const <BoxShadow>[
      BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
  );
}

enum _Thumb { start, end }

/// The interactive body of a `ZenRangeSlider`: a track with a **start** and an **end** thumb that
/// are each their own focus stop and accessibility node, so a keyboard or screen-reader user can
/// name and move either one.
///
/// Neither Flutter's Material range slider nor anything in Cupertino lets a thumb carry its own
/// name, so the body draws both idioms itself from a [ZenRangeSliderStyle].
///
/// The thumbs may meet but never cross: the start thumb stops at the end value, the end thumb at
/// the start value, and moving one never changes the other. When they are together, a drag moves
/// the thumb in the direction it is dragged.
///
/// Internal to the package: not exported.
class ZenRangeSliderBody extends StatefulWidget {
  /// Creates the body.
  const ZenRangeSliderBody({
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.startLabel,
    required this.endLabel,
    required this.format,
    required this.style,
    super.key,
  });

  /// The current range, already inside `[min, max]` and ordered.
  final RangeValues values;

  /// The smallest value.
  final double min;

  /// The largest value.
  final double max;

  /// Equal steps the range is divided into; null is continuous.
  final int? divisions;

  /// Called with the new range; null disables the slider.
  final ValueChanged<RangeValues>? onChanged;

  /// The accessible name of the start thumb.
  final String startLabel;

  /// The accessible name of the end thumb.
  final String endLabel;

  /// Writes a value as text for the screen reader.
  final String Function(double) format;

  /// The platform's look.
  final ZenRangeSliderStyle style;

  @override
  State<ZenRangeSliderBody> createState() => _ZenRangeSliderBodyState();
}

class _ZenRangeSliderBodyState extends State<ZenRangeSliderBody> {
  /// The hit area of a thumb, and the room kept at each end of the track so it fits.
  static const double _target = 48;
  static const double _inset = _target / 2;

  final FocusNode _startFocus = FocusNode(debugLabel: 'ZenRangeSlider start');
  final FocusNode _endFocus = FocusNode(debugLabel: 'ZenRangeSlider end');

  _Thumb? _dragging;
  bool _tied = false;
  double _grabOffset = 0;

  /// Where the pointer went down. The gesture only starts once the pointer has travelled past the
  /// touch slop, so the thumb under the finger has to be chosen from here, not from there.
  double _downX = 0;

  bool get _enabled => widget.onChanged != null;

  @override
  void dispose() {
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  double _fraction(double value) => (value - widget.min) / (widget.max - widget.min);

  /// The x position of [value] on a track [width] wide.
  double _x(double value, double width, bool rtl) {
    final double f = _fraction(value);
    return _inset + (rtl ? 1 - f : f) * (width - 2 * _inset);
  }

  double _valueAt(double x, double width, bool rtl) {
    final double f = ((x - _inset) / (width - 2 * _inset)).clamp(0.0, 1.0);
    return widget.min + (rtl ? 1 - f : f) * (widget.max - widget.min);
  }

  void _emit(double start, double end) {
    if (start == widget.values.start && end == widget.values.end) return;
    widget.onChanged?.call(RangeValues(start, end));
  }

  void _move(_Thumb thumb, double raw) {
    final RangeValues v = widget.values;
    final double snapped = zenSliderSnap(raw, widget.min, widget.max, widget.divisions);
    if (thumb == _Thumb.start) {
      _emit(snapped > v.end ? v.end : snapped, v.end);
    } else {
      _emit(v.start, snapped < v.start ? v.start : snapped);
    }
  }

  /// Picks the thumb a pointer at [x] belongs to; null when both are equally near, which is
  /// settled by the first movement.
  _Thumb? _nearest(double x, double width, bool rtl) {
    final double toStart = (_x(widget.values.start, width, rtl) - x).abs();
    final double toEnd = (_x(widget.values.end, width, rtl) - x).abs();
    if (toStart == toEnd) return null;
    return toStart < toEnd ? _Thumb.start : _Thumb.end;
  }

  void _focus(_Thumb thumb) => (thumb == _Thumb.start ? _startFocus : _endFocus).requestFocus();

  void _onTapUp(TapUpDetails details, double width, bool rtl) {
    if (!_enabled) return;
    final double value = _valueAt(details.localPosition.dx, width, rtl);
    final _Thumb thumb =
        _nearest(details.localPosition.dx, width, rtl) ??
        (value > widget.values.end ? _Thumb.end : _Thumb.start);
    _focus(thumb);
    _move(thumb, value);
  }

  void _onDragDown(DragDownDetails details) => _downX = details.localPosition.dx;

  void _onDragStart(double width, bool rtl) {
    if (!_enabled) return;
    _dragging = _nearest(_downX, width, rtl);
    _tied = _dragging == null;
    if (_dragging != null) {
      final double at = _dragging == _Thumb.start ? widget.values.start : widget.values.end;
      _grabOffset = _x(at, width, rtl) - _downX;
      _focus(_dragging!);
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double width, bool rtl) {
    if (!_enabled) return;
    final double x = details.localPosition.dx;
    if (_tied) {
      // Together: the thumb that can move the way the pointer went is the one grabbed. Until it
      // has gone somewhere, neither is.
      if (x == _downX) return;
      _dragging = ((x > _downX) != rtl) ? _Thumb.end : _Thumb.start;
      _tied = false;
      _grabOffset = _x(widget.values.start, width, rtl) - _downX;
      _focus(_dragging!);
    }
    final _Thumb? thumb = _dragging;
    if (thumb == null) return;
    _move(thumb, _valueAt(x + _grabOffset, width, rtl));
  }

  void _onDragEnd() {
    _dragging = null;
    _tied = false;
  }

  KeyEventResult _onKey(_Thumb thumb, KeyEvent event, bool rtl) {
    if (!_enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final RangeValues v = widget.values;
    final bool start = thumb == _Thumb.start;
    final double? target = zenSliderKeyTarget(
      event.logicalKey,
      value: start ? v.start : v.end,
      lowest: start ? widget.min : v.start,
      highest: start ? v.end : widget.max,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      rtl: rtl,
    );
    if (target == null) return KeyEventResult.ignored;
    if (start) {
      _emit(target, v.end);
    } else {
      _emit(v.start, target);
    }
    return KeyEventResult.handled;
  }

  /// The disabled look, as an opaque colour: the track's two parts overlap, and translucent ones
  /// would darken where they do.
  Color _disabled(BuildContext context, double opacity) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(scheme.onSurface.withValues(alpha: opacity), scheme.surface);
  }

  /// One thumb: a focus stop and one slider node (name, value, increment, decrement) with the
  /// thumb drawn inside it. Pointer input is the body's, so the thumb itself ignores it.
  Widget _thumb(_Thumb thumb, double width, bool rtl) {
    final RangeValues v = widget.values;
    final bool start = thumb == _Thumb.start;
    final double value = start ? v.start : v.end;
    final double lowest = start ? widget.min : v.start;
    final double highest = start ? v.end : widget.max;
    final double step = zenSliderStep(widget.min, widget.max, widget.divisions);
    double stepped(double by) => zenSliderClamp(
      zenSliderSnap(value + by, widget.min, widget.max, widget.divisions),
      lowest,
      highest,
    );
    void set(double next) => start ? _emit(next, v.end) : _emit(v.start, next);
    final ZenRangeSliderStyle style = widget.style;

    return Positioned(
      left: _x(value, width, rtl) - _target / 2,
      top: 0,
      width: _target,
      height: _target,
      child: Semantics(
        container: true,
        slider: true,
        enabled: _enabled,
        label: start ? widget.startLabel : widget.endLabel,
        value: widget.format(value),
        increasedValue: widget.format(stepped(step)),
        decreasedValue: widget.format(stepped(-step)),
        onIncrease: _enabled ? () => set(stepped(step)) : null,
        onDecrease: _enabled ? () => set(stepped(-step)) : null,
        child: Focus(
          focusNode: start ? _startFocus : _endFocus,
          canRequestFocus: _enabled,
          onKeyEvent: (FocusNode node, KeyEvent event) => _onKey(thumb, event, rtl),
          child: IgnorePointer(
            child: Center(
              child: FocusRing(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _enabled ? style.thumbColor : _disabled(context, 0.38),
                    border: Border.all(
                      color: _enabled ? style.thumbBorderColor : _disabled(context, 0.38),
                    ),
                    boxShadow: _enabled ? style.thumbShadow : const <BoxShadow>[],
                  ),
                  child: SizedBox.square(dimension: style.thumbDiameter),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final ZenRangeSliderStyle style = widget.style;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double a = _x(widget.values.start, width, rtl);
        final double b = _x(widget.values.end, width, rtl);
        return SizedBox(
          height: _target,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) => _onTapUp(d, width, rtl),
            onHorizontalDragDown: _onDragDown,
            onHorizontalDragStart: (DragStartDetails d) => _onDragStart(width, rtl),
            onHorizontalDragUpdate: (DragUpdateDetails d) => _onDragUpdate(d, width, rtl),
            onHorizontalDragEnd: (_) => _onDragEnd(),
            onHorizontalDragCancel: _onDragEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrackPainter(
                      from: a < b ? a : b,
                      to: a < b ? b : a,
                      inset: _inset,
                      height: style.trackHeight,
                      active: _enabled ? style.activeColor : _disabled(context, 0.38),
                      inactive: _enabled ? style.inactiveColor : _disabled(context, 0.12),
                    ),
                  ),
                ),
                _thumb(_Thumb.start, width, rtl),
                _thumb(_Thumb.end, width, rtl),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Paints the track: all of it in the inactive colour, and the stretch between the thumbs in the
/// active one.
class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.from,
    required this.to,
    required this.inset,
    required this.height,
    required this.active,
    required this.inactive,
  });

  final double from;
  final double to;
  final double inset;
  final double height;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Radius radius = Radius.circular(height / 2);
    RRect bar(double left, double right) =>
        RRect.fromLTRBR(left, y - height / 2, right, y + height / 2, radius);
    canvas.drawRRect(bar(inset, size.width - inset), Paint()..color = inactive);
    canvas.drawRRect(bar(from, to), Paint()..color = active);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      from != old.from ||
      to != old.to ||
      height != old.height ||
      active != old.active ||
      inactive != old.inactive;
}
