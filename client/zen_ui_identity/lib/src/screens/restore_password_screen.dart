import 'package:zen_core/zen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/identity_messages.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_text_field.dart';

/// Screen for initiating password reset via email.
class RestorePasswordScreen extends ConsumerStatefulWidget {
  final VoidCallback? onRestoreSuccess;
  final VoidCallback? onBackClick;
  final IdentityMessages messages;

  const RestorePasswordScreen({
    super.key,
    required this.messages,
    this.onRestoreSuccess,
    this.onBackClick,
  });

  @override
  ConsumerState<RestorePasswordScreen> createState() =>
      _RestorePasswordScreenState();
}

class _RestorePasswordScreenState extends ConsumerState<RestorePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(identitySessionStoreProvider.notifier);
    final result = await controller.restorePassword(
      _emailController.text.trim(),
    );

    if (!mounted) return;

    result.fold(
      (_) {
        // Success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.messages.resetLinkSentSuccess)),
        );

        widget.onRestoreSuccess?.call();
      },
      (ZenError error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.messages.error(error)),
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
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();

    return Scaffold(
      backgroundColor: theme.surfaceColor,
      appBar: AppBar(
        title: Text(widget.messages.restorePasswordTitle),
        leading: widget.onBackClick != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: widget.messages.backButtonTooltip,
                onPressed: widget.onBackClick,
              )
            : null,
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
                  Text(
                    widget.messages.restorePasswordInfo,
                    style: theme.subtitleStyle,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityTextField(
                    label: widget.messages.emailLabel,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return widget.messages.validationRequired;
                      }
                      if (!value.contains('@')) {
                        return widget.messages.validationEmail;
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: theme.spacing * 2),
                  IdentityButton(
                    text: widget.messages.sendResetLinkButton,
                    isLoading: ref
                        .watch(identitySessionStoreProvider)
                        .isLoading,
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
