import 'package:flutter/services.dart';

/// The arithmetic every jZen slider shares, kept in one place so the single-value and the range
/// slider answer the same questions the same way.
///
/// A slider offers values from `min` to `max`. With `divisions` they are the `divisions + 1`
/// evenly spaced values between them (`step = (max - min) / divisions`); without, any value in
/// the range.

/// The default text for a slider value: whole numbers without a decimal point, otherwise two
/// places. An app that shows units or a locale's separators passes its own formatter.
String zenSliderFormat(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(2);

/// Whether `min`, `max` and `divisions` describe a usable slider.
bool zenSliderBoundsAreValid(double min, double max, int? divisions) =>
    min.isFinite && max.isFinite && min < max && (divisions == null || divisions > 0);

/// [value] limited to `[min, max]`. A NaN, which no range contains, becomes [min].
double zenSliderClamp(double value, double min, double max) {
  if (value.isNaN) return min;
  return value < min ? min : (value > max ? max : value);
}

/// [value] moved to the nearest of the slider's values when it has [divisions], then limited to
/// `[min, max]`.
double zenSliderSnap(double value, double min, double max, int? divisions) {
  final double clamped = zenSliderClamp(value, min, max);
  if (divisions == null) return clamped;
  final double step = (max - min) / divisions;
  return zenSliderClamp(min + ((clamped - min) / step).roundToDouble() * step, min, max);
}

/// How far one arrow key press or one screen-reader increment moves a value: one division, or a
/// tenth of the range when the slider is continuous — the unit Flutter's own sliders use.
double zenSliderStep(double min, double max, int? divisions) => (max - min) / (divisions ?? 10);

/// How far Page Up and Page Down move a value: a quarter of the range when continuous, about a
/// tenth of it in whole divisions otherwise, and never less than a step.
double zenSliderPage(double min, double max, int? divisions) {
  final double step = zenSliderStep(min, max, divisions);
  if (divisions == null) return (max - min) / 4;
  final double tenth = (max - min) / 10;
  return tenth < step ? step : (tenth / step).ceilToDouble() * step;
}

final Set<LogicalKeyboardKey> _arrows = <LogicalKeyboardKey>{
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
};

/// The value a key moves a slider thumb at [value] to, or null when the key is not a slider key.
///
/// Arrow keys move by one step — Right and Up add, Left and Down subtract, with Left and Right
/// swapped in a right-to-left layout so the arrows follow the track. Page Up and Page Down move
/// by a page, Home goes to [lowest] and End to [highest]: the bounds this thumb may reach, which
/// for a range slider's thumbs are the other thumb rather than the slider's own ends. With
/// [arrows] false the arrow keys are not handled, for a slider that already moves on them.
double? zenSliderKeyTarget(
  LogicalKeyboardKey key, {
  bool arrows = true,
  required double value,
  required double lowest,
  required double highest,
  required double min,
  required double max,
  required int? divisions,
  required bool rtl,
}) {
  final double step = zenSliderStep(min, max, divisions);
  final double page = zenSliderPage(min, max, divisions);
  if (!arrows && _arrows.contains(key)) return null;
  final double? target = switch (key) {
    LogicalKeyboardKey.arrowRight => value + (rtl ? -step : step),
    LogicalKeyboardKey.arrowLeft => value + (rtl ? step : -step),
    LogicalKeyboardKey.arrowUp => value + step,
    LogicalKeyboardKey.arrowDown => value - step,
    LogicalKeyboardKey.pageUp => value + page,
    LogicalKeyboardKey.pageDown => value - page,
    LogicalKeyboardKey.home => lowest,
    LogicalKeyboardKey.end => highest,
    _ => null,
  };
  if (target == null) return null;
  // Clamped again after snapping: a bound the app supplied off the grid must still hold.
  return zenSliderClamp(
    zenSliderSnap(zenSliderClamp(target, lowest, highest), min, max, divisions),
    lowest,
    highest,
  );
}
