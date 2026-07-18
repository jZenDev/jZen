import 'package:zen_identity/zen_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/identity_messages.dart';
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
  final IdentityMessages messages;

  const LoginScreen({
    super.key,
    required this.messages,
    this.onLoginSuccess,
    this.onLoginSuccessWithIdentity,
    this.onRegisterClick,
    this.onForgotPasswordClick,
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
    final result = await controller.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

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
            content: Text(widget.messages.error(failure)),
            backgroundColor: Theme.of(
              context,
            ).extension<IdentityThemeExtension>()?.errorColor,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Preload messages if not loaded? Usually done at app startup.
    // We assume messages are ready or we use them synchronously.

    final state = ref.watch(identitySessionStoreProvider);
    final isLoading = state.isLoading;
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();

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
                    widget.messages.loginTitle,
                    style: theme.titleStyle.copyWith(color: theme.brandColor),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityTextField(
                    label: widget.messages.emailLabel,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return widget.messages.validationRequired;
                      }
                      // Basic email regex or just let backend validate
                      if (!value.contains('@')) {
                        return widget.messages.validationEmail;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityTextField(
                    label: widget.messages.passwordLabel,
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return widget.messages.validationRequired;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing / 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IdentityButton(
                      text: widget
                          .messages
                          .restorePasswordTitle, // "Reset Password" usually
                      variant: IdentityButtonVariant.text,
                      onPressed: isLoading
                          ? null
                          : widget.onForgotPasswordClick,
                    ),
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityButton(
                    text: widget.messages.loginButton,
                    isLoading: isLoading,
                    onPressed: _submit,
                  ),
                  SizedBox(height: theme.spacing),
                  const Divider(),
                  IdentityButton(
                    text: widget.messages.registerTitle, // "Sign Up" usually
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
