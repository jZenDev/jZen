import 'package:email_validator/email_validator.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart' as pb;

import 'identity_contracts.dart';
import 'zen_identity_config.dart';

/// A Supabase-backed [IdentityRepository] (TA-5).
///
/// This is the implementation DartZen never had: it implements the declared
/// [IdentityRepository] interface exactly (`getCurrentIdentity`, `loginWithEmail`,
/// `registerWithEmail`, `restorePassword`, `logout`), discarding the disjoint
/// `FirestoreIdentityRepository` method set. It is backed by the zen-identity Supabase
/// endpoints, called through zen_transport's dual-mode [pb.ZenClient] with typed proto
/// messages; the wire format (JSON or Protobuf) is chosen compile-time by the transport layer.
///
/// The session lives in httpOnly cookies the server sets and SmallRye JWT reads; on the web
/// the browser attaches them automatically. (Native cookie persistence is a transport concern
/// addressed by zen_demo in ROADMAP step 4; it does not affect this repository's contract.)
class SupabaseIdentityRepository implements IdentityRepository {
  /// Creates a repository. [client] is injectable for tests; by default it targets the
  /// compile-time [zenApiUrl].
  SupabaseIdentityRepository({pb.ZenClient? client})
    : _client = client ?? pb.ZenClient(baseUrl: zenApiUrl);

  final pb.ZenClient _client;

  static const String _login = '/api/v1/auth/login';
  static const String _register = '/api/v1/auth/register';
  static const String _restorePassword = '/api/v1/auth/restore-password';
  static const String _logout = '/api/v1/auth/logout';
  static const String _identity = '/api/v1/auth/identity';

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async {
    final result = await _client.get(pb.Identity.new, _identity);
    return result.fold(
      // A 204 (anonymous) decodes to an empty Identity; an empty id means "no session".
      (identity) => ZenResult.ok(identity.id.isEmpty ? null : _toContract(identity)),
      (error) => ZenResult.err(error),
    );
  }

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) {
    return _authenticate(
      email: email,
      path: _login,
      body: pb.LoginRequest(email: email, password: password),
    );
  }

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _authenticate(
      email: email,
      path: _register,
      body: pb.RegisterRequest(email: email, password: password),
    );
  }

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async {
    if (!EmailValidator.validate(email)) {
      return const ZenResult.err(ZenValidationError('Invalid email address'));
    }
    final result = await _client.post(
      pb.Identity.new,
      _restorePassword,
      body: pb.RestorePasswordRequest(email: email),
    );
    return result.fold((_) => const ZenResult<void>.ok(null), ZenResult<void>.err);
  }

  @override
  Future<ZenResult<void>> logout() async {
    final result = await _client.post(pb.Identity.new, _logout);
    return result.fold((_) => const ZenResult<void>.ok(null), ZenResult<void>.err);
  }

  /// Shared login/register path: validate the email, POST the typed [body], map the reply.
  Future<ZenResult<IdentityContract>> _authenticate({
    required String email,
    required String path,
    required GeneratedMessage body,
  }) async {
    if (!EmailValidator.validate(email)) {
      return const ZenResult.err(ZenValidationError('Invalid email address'));
    }
    final result = await _client.post(pb.Identity.new, path, body: body);
    return result.fold(
      (identity) => ZenResult.ok(_toContract(identity)),
      (error) => ZenResult.err(error),
    );
  }

  /// Maps the wire [pb.Identity] proto to the transport-agnostic [IdentityContract].
  IdentityContract _toContract(pb.Identity identity) => IdentityContract(
    id: identity.id,
    lifecycle: IdentityLifecycleContract(
      state: identity.lifecycleState.isEmpty ? 'active' : identity.lifecycleState,
      reason: identity.lifecycleReason.isEmpty ? null : identity.lifecycleReason,
    ),
    authority: AuthorityContract(
      roles: identity.roles.toList(),
      capabilities: identity.capabilities.toList(),
    ),
    createdAt: identity.createdAtMs.toInt(),
  );
}
