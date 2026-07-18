import 'package:zen_core/zen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/identity_messages.dart';
import '../state/identity_session_store.dart';
import '../theme/identity_theme_extension.dart';
import '../widgets/identity_status_chip.dart';

/// Detailed view of user roles and authorities.
class AuthorityRolesScreen extends ConsumerWidget {
  final IdentityMessages messages;

  const AuthorityRolesScreen({super.key, required this.messages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(identitySessionStoreProvider);
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();

    return Scaffold(
      backgroundColor: theme.surfaceColor,
      appBar: AppBar(
        title: Text(messages.rolesTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.brandColor,
      ),
      body: state.when(
        data: (identity) {
          if (identity == null) {
            return const Center(child: Text("Not authenticated"));
          }

          return ListView(
            padding: theme.containerPadding,
            children: [
              if (identity.authority.roles.isEmpty)
                Center(
                  child: Text("No roles assigned", style: theme.subtitleStyle),
                ),
              ...identity.authority.roles.map((role) {
                return Card(
                  margin: EdgeInsets.only(bottom: theme.spacing),
                  child: Padding(
                    padding: EdgeInsets.all(theme.spacing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [IdentityStatusChip(label: role.name)]),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Text(
            messages.error(
              err is ZenError ? err : ZenUnknownError(err.toString()),
            ),
          ),
        ),
      ),
    );
  }
}
