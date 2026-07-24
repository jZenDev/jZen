import 'package:zen_identity/zen_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/identity_localizations.dart';
import '../l10n/identity_error_text.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_text_field.dart';

/// Screen for user registration with email and password.
class RegisterScreen extends ConsumerStatefulWidget {
  final VoidCallback? onRegisterSuccess;
  final ValueChanged<Identity>? onRegisterSuccessWithIdentity;
  final VoidCallback? onLoginClick;

  const RegisterScreen({
    super.key,
    this.onRegisterSuccess,
    this.onRegisterSuccessWithIdentity,
    this.onLoginClick,
  });

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(identitySessionStoreProvider.notifier);
    final result = await controller.register(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    final messages = IdentityLocalizations.of(context);

    result.fold(
      (identity) {
        widget.onRegisterSuccess?.call();
        widget.onRegisterSuccessWithIdentity?.call(identity);
      },
      (failure) {
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
      appBar: AppBar(
        title: Text(messages.registerTitle), // "Sign Up"
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.brandColor,
      ),
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
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return messages.validationRequired;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing),
                  IdentityTextField(
                    label: messages.confirmPasswordLabel,
                    controller: _confirmPasswordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return messages.validationPasswordMismatch;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityButton(
                    text: messages.registerButton,
                    isLoading: isLoading,
                    onPressed: _submit,
                  ),
                  SizedBox(height: theme.spacing),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(messages.alreadyHaveAccount, overflow: TextOverflow.ellipsis),
                        IdentityButton(
                          text: messages.loginButton,
                          variant: IdentityButtonVariant.text,
                          onPressed: isLoading ? null : widget.onLoginClick,
                        ),
                      ],
                    ),
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
