/// Identity capability for the jZen client.
///
/// Exposes the provider-agnostic [IdentityRepository] contract and identity domain models,
/// plus the Supabase-backed [SupabaseIdentityRepository] that implements the contract over
/// the zen-identity endpoints.
library;

export 'src/identity_contracts.dart';
export 'src/identity_models.dart';
export 'src/supabase_identity_repository.dart';
export 'src/zen_identity_config.dart';
