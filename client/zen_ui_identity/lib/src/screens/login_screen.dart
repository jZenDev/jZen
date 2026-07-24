import 'package:zen_identity/zen_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/identity_localizations.dart';
import '../l10n/identity_error_text.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_text_field.dart';

/// Screen for user login with email and password.
class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;
  final ValueChanged<Identity>? onLoginSuccessWithIdentity;
  final VoidCallback? onRegisterClick;
  final VoidCallback? onForgotPasswordClick;

  /// Optional informational widget shown beneath the title, before the fields. The screen ships
  /// no wording of its own, so an app that needs to say something on the login page (a demo
  /// hint, a maintenance notice) supplies it here already localized. Null renders nothing, so
  /// the default screen is unchanged.
  final Widget? banner;

  const LoginScreen({
    super.key,
    this.onLoginSuccess,
    this.onLoginSuccessWithIdentity,
    this.onRegisterClick,
    this.onForgotPasswordClick,
    this.banner,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Local loading state to coordinate with provider if needed,
  // though provider has its own async state.
  // We use provider state for the button loading indicator.

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(identitySessionStoreProvider.notifier);
    final result = await controller.login(_emailController.text.trim(), _passwordController.text);

    if (!mounted) return;
    final messages = IdentityLocalizations.of(context);

    result.fold(
      (identity) {
        // Success
        widget.onLoginSuccess?.call();
        widget.onLoginSuccessWithIdentity?.call(identity);
      },
      (failure) {
        // Error handling
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(messages.errorText(failure)),
            backgroundColor: Theme.of(context).extension<IdentityThemeExtension>()?.errorColor,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = IdentityLocalizations.of(context);
    final state = ref.watch(identitySessionStoreProvider);
    final isLoading = state.isLoading;
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
                    messages.loginTitle,
                    style: theme.titleStyle.copyWith(color: theme.brandColor),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: theme.spacing * 2),
                  if (widget.banner != null) ...[
                    widget.banner!,
                    SizedBox(height: theme.spacing * 2),
                  ],
                  IdentityTextField(
                    label: messages.emailLabel,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return messages.validationRequired;
                      }
                      // Basic email regex or just let backend validate
                      if (!value.contains('@')) {
                        return messages.validationEmail;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityTextField(
                    label: messages.passwordLabel,
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return messages.validationRequired;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing / 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IdentityButton(
                      text: messages.restorePasswordTitle, // "Reset Password" usually
                      variant: IdentityButtonVariant.text,
                      onPressed: isLoading ? null : widget.onForgotPasswordClick,
                    ),
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityButton(
                    text: messages.loginButton,
                    isLoading: isLoading,
                    onPressed: _submit,
                  ),
                  SizedBox(height: theme.spacing),
                  const Divider(),
                  IdentityButton(
                    text: messages.registerTitle, // "Sign Up" usually
                    variant: IdentityButtonVariant.text,
                    onPressed: isLoading ? null : widget.onRegisterClick,
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
