import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/identity_localizations.dart';
import '../l10n/identity_error_text.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_button.dart';
import '../widgets/identity_status_chip.dart';

/// Displays user profile information and actions.
class ProfileScreen extends ConsumerWidget {
  final VoidCallback? onLogoutSuccess;
  final ValueChanged<Identity>? onLogoutSuccessWithIdentity;
  final VoidCallback? onBackClick;

  const ProfileScreen({
    super.key,
    this.onLogoutSuccess,
    this.onLogoutSuccessWithIdentity,
    this.onBackClick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = IdentityLocalizations.of(context);
    final state = ref.watch(identitySessionStoreProvider);
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();

    return Scaffold(
      backgroundColor: theme.surfaceColor,
      appBar: AppBar(
        title: Text(messages.profileTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.brandColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: messages.logoutButton,
            onPressed: () async {
              final identity = ref.read(identitySessionStoreProvider).value;
              await ref.read(identitySessionStoreProvider.notifier).logout();
              onLogoutSuccess?.call();
              if (identity != null) {
                onLogoutSuccessWithIdentity?.call(identity);
              }
            },
          ),
        ],
      ),
      body: state.when(
        data: (identity) {
          if (identity == null) {
            return Center(child: Text(messages.notAuthenticated));
          }
          final subject = identity.id.value;

          return ListView(
            padding: theme.containerPadding,
            children: [
              Semantics(
                label: messages.profileAvatarLabel,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: theme.brandColor.withValues(alpha: 0.1),
                  child: Text(
                    subject.substring(0, 1).toUpperCase(),
                    style: theme.titleStyle.copyWith(color: theme.brandColor),
                  ),
                ),
              ),
              SizedBox(height: theme.spacing),
              Text(subject, style: theme.titleStyle, textAlign: TextAlign.center),
              SizedBox(height: theme.spacing),
              Text(messages.rolesLabel, style: theme.subtitleStyle),
              SizedBox(height: theme.spacing / 2),
              Wrap(
                spacing: 8,
                children: identity.authority.roles.map((role) {
                  return IdentityStatusChip(label: role.name, isOutline: true);
                }).toList(),
              ),
              SizedBox(height: theme.spacing * 2),
              IdentityButton(
                text: messages.logoutButton,
                variant: IdentityButtonVariant.secondary,
                onPressed: () async {
                  final identity = ref.read(identitySessionStoreProvider).value;
                  await ref.read(identitySessionStoreProvider.notifier).logout();
                  onLogoutSuccess?.call();
                  if (identity != null) {
                    onLogoutSuccessWithIdentity?.call(identity);
                  }
                },
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Text(messages.errorText(err is ZenError ? err : ZenUnknownError(err.toString()))),
        ),
      ),
    );
  }
}
