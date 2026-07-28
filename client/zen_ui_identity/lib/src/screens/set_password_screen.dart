import 'package:zen_core/zen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/identity_localizations.dart';
import '../l10n/identity_error_text.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_text_field.dart';

/// Screen for choosing a new password for the current session.
///
/// It is where a password-recovery link ends up: the link signed the user in, and this is the
/// step that makes that worth anything. The user is already authenticated by the time they see
/// it, which is why there is no email field and no old-password field — the session is the proof.
///
/// It has no way back on purpose. An app shows it while `passwordResetRequiredProvider` is true,
/// so leaving it means setting a password; a user who dismissed it would be signed into an
/// account whose password they still do not know.
class SetPasswordScreen extends ConsumerStatefulWidget {
  /// Called once the new password has been accepted.
  final VoidCallback? onPasswordSet;

  const SetPasswordScreen({super.key, this.onPasswordSet});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Local submit state drives the button spinner, for the reason the login screen gives: the
  // session store must not flip to loading mid-submit, or this screen is disposed and the result
  // it is waiting to show goes with it.
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    final controller = ref.read(identitySessionStoreProvider.notifier);
    final result = await controller.setPassword(_passwordController.text);

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    final messages = IdentityLocalizations.of(context);

    result.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messages.passwordChangedSuccess)));
        widget.onPasswordSet?.call();
      },
      (ZenError error) {
        // Password rules are the identity provider's, so a rejection ("too weak") arrives as a
        // coded error and is rendered like any other. The screen states no rule of its own, which
        // is what keeps it from contradicting the server.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(messages.errorText(error)),
            backgroundColor: Theme.of(context).extension<IdentityThemeExtension>()?.errorColor,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = IdentityLocalizations.of(context);
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();

    return Scaffold(
      backgroundColor: theme.surfaceColor,
      body: Center(
        child: SingleChildScrollView(
          padding: theme.containerPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    messages.setPasswordTitle,
                    style: theme.titleStyle.copyWith(color: theme.brandColor),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: theme.spacing),
                  Text(
                    messages.setPasswordInfo,
                    style: theme.subtitleStyle,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityTextField(
                    label: messages.newPasswordLabel,
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.isEmpty) ? messages.validationRequired : null,
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityTextField(
                    label: messages.confirmPasswordLabel,
                    controller: _confirmController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return messages.validationRequired;
                      }
                      if (value != _passwordController.text) {
                        return messages.validationPasswordMismatch;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityButton(
                    text: messages.setPasswordButton,
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
