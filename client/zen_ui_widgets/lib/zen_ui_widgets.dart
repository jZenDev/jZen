/// Shared adaptive widgets for jZen applications: the chrome that is neither navigation
/// (`zen_ui_navigation`) nor identity (`zen_ui_identity`).
///
/// Every widget here renders Cupertino on Apple platforms (iOS and macOS) and Material
/// everywhere else, chosen by compile-time constants from `zen_core` so each build tree-shakes
/// the idiom it never uses. The framework owns the shape and the accessibility treatment — one
/// announcement per control, a visible focus ring, AA contrast — and the application supplies
/// the content and the callbacks.
///
/// * [showAdaptivePresentation] — a form/detail overlay: a sheet on native mobile, a dialog on
///   desktop and web.
/// * [showZenDetail], [ZenDetailHost] — the detail of a list: beside it when the window is wide
///   (an in-layout pane on Apple, a side sheet elsewhere), a full-screen push when it is narrow.
/// * [ZenPageRoute], [ZenPageTransitions] — what a pushed page does on each platform: the iOS
///   slide on iOS, a short fade on macOS.
/// * [ZenButton] — primary, secondary and text buttons.
/// * [ZenIconButton] — an icon-only button, always named by a required label; it can carry a
///   count badge.
/// * [ZenSelect], [ZenSegmentedControl], [ZenSwitchRow] — a choice from a list, a small set of
///   exclusive choices, and an on/off setting.
/// * [ZenDateField], [ZenDateRangeField] — a date and a from/to pair whose order is enforced.
/// * [ZenAmountField], [ZenAmountRangeField] — a decimal number and a min/max pair whose order
///   is reported; the number's meaning stays with the app.
/// * [ZenTextField] — a labelled text input, the base of [ZenAmountField].
/// * [ZenProgressIndicator], [ZenProgressBar] — an indeterminate spinner and a determinate bar.
/// * [ZenPageScaffold] — a page: a top bar (title, back, actions) over a body.
/// * [showZenMessage] — a transient message: a snack bar on Material, a toast on Apple.
/// * [FocusRing] — the focus indicator the above use, for an app's own controls.
///
/// The few strings these controls speak are owned by [ZenWidgetsLocalizations]; register
/// [zenWidgetsLocaleDelegate] to use them.
library;

export 'src/adaptive_presentation.dart';
export 'src/focus_ring.dart' show FocusRing, zenFocusRingWidth;
export 'src/l10n/generated/zen_widgets_localizations.dart';
// The per-locale implementations, exported so an application can translate this package's
// strings itself (ADR-044): subclass the fallback one and override only the getters it wants.
export 'src/l10n/generated/zen_widgets_localizations_en.dart';
export 'src/l10n/generated/zen_widgets_localizations_uk.dart';
export 'src/l10n/zen_widgets_locale_delegate.dart';
export 'src/picker_field.dart' show ZenPickerField;
export 'src/zen_amount_field.dart'
    show ZenAmountField, ZenAmountInputFormatter, normalizeAmount, parseAmount, zenDecimalSeparator;
export 'src/zen_amount_range_field.dart' show ZenAmountRangeField;
export 'src/zen_button.dart' show ZenButton, ZenButtonVariant, zenButtonMinHeight;
export 'src/zen_date_field.dart' show ZenDateField, zenDefaultFirstDate, zenDefaultLastDate;
export 'src/zen_date_range_field.dart' show ZenDateRangeField;
export 'src/zen_detail.dart' show showZenDetail;
export 'src/zen_detail_host.dart' show ZenDetailHost, ZenDetailHostState, zenDetailMinWidth;
export 'src/zen_icon_button.dart' show ZenIconButton, zenIconButtonSize;
export 'src/zen_message.dart' show showZenMessage, zenMessageDuration;
export 'src/zen_page_route.dart' show ZenPageRoute;
export 'src/zen_page_scaffold.dart' show ZenPageScaffold;
export 'src/zen_page_transitions.dart' show ZenFadePageTransitionsBuilder, ZenPageTransitions;
export 'src/zen_progress_bar.dart' show ZenProgressBar;
export 'src/zen_progress_indicator.dart' show ZenProgressIndicator;
export 'src/zen_segmented_control.dart' show ZenSegment, ZenSegmentedControl;
export 'src/zen_select.dart' show ZenSelect;
export 'src/zen_switch_row.dart' show ZenSwitchRow;
export 'src/zen_text_field.dart' show ZenTextField;
