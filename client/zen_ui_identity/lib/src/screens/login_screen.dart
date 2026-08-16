import 'package:zen_identity/zen_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/identity_localizations.dart';
import '../l10n/identity_error_text.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_text_field.dart';

/// What an email link left the user with by the time they reached the login screen. Only the two
/// cases that need saying: the ones that end signed in never render this screen at all.
enum _Landing { expired, confirmed }

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

  // Local submit state drives the button spinner. The session store deliberately does not flip to
  // loading during a login attempt (that would splash the app and dispose this screen), so the
  // in-progress state is tracked here instead of read from the provider.
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Reaching the login screen after following an email link means the link did not sign the
    // user in — either it carried no session to exchange, or the exchange was refused. Both are
    // worth saying out loud: without a word here the user is looking at a login form with no idea
    // whether their confirmation worked. The link itself was parsed and consumed during the
    // session load, so this reads the outcome rather than the URL, which by now has been cleaned.
    final link = ref.read(authLinkProvider);
    final _Landing? landing = switch (link.kind) {
      ZenAuthLinkKind.failed => _Landing.expired,
      ZenAuthLinkKind.confirmedWithoutSession => _Landing.confirmed,
      _ => ref.read(identitySessionStoreProvider.notifier).linkRejected ? _Landing.expired : null,
    };

    if (landing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messages = IdentityLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (landing) {
              _Landing.expired => messages.linkExpiredBanner,
              _Landing.confirmed => messages.emailConfirmedBanner,
            }),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    final controller = ref.read(identitySessionStoreProvider.notifier);
    final result = await controller.login(_emailController.text.trim(), _passwordController.text);

    if (!mounted) return;
    setState(() => _isSubmitting = false);
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
    final isLoading = _isSubmitting;
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
