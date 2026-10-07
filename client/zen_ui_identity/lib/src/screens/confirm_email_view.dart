import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenPageScaffold;

import '../l10n/generated/identity_localizations.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';

/// The dedicated "check your email" screen shown after a registration that requires email
/// confirmation — a full screen rather than a popup, because the user has left the form behind
/// and their next action is in their inbox, not on this page.
class ConfirmEmailView extends StatelessWidget {
  const ConfirmEmailView({
    super.key,
    required this.email,
    required this.theme,
    required this.messages,
    required this.onBackToLogin,
  });

  final String email;
  final IdentityThemeExtension theme;
  final IdentityLocalizations messages;
  final VoidCallback? onBackToLogin;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ZenPageScaffold(
      backgroundColor: theme.surfaceColor,
      foregroundColor: theme.brandColor,
      body: Center(
        child: SingleChildScrollView(
          padding: theme.containerPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_unread_outlined, size: 64, color: theme.brandColor),
                const SizedBox(height: 24),
                Text(
                  messages.confirmEmailTitle,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: theme.brandColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(messages.confirmEmailBody, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                IdentityButton(text: messages.loginButton, onPressed: onBackToLogin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
