// This is a generated file - do not edit.
//
// Generated from zen/v1/identity.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The authenticated identity / session payload. Returned by login, register, refresh, and
/// the get-current-identity probe: an id, a lifecycle (state + optional reason), an authority
/// (roles + capabilities), and a creation timestamp. An Identity with an empty `id` denotes
/// "no session" (the anonymous probe result).
class Identity extends $pb.GeneratedMessage {
  factory Identity({
    $core.String? id,
    $core.String? lifecycleState,
    $core.String? lifecycleReason,
    $core.Iterable<$core.String>? roles,
    $core.Iterable<$core.String>? capabilities,
    $fixnum.Int64? createdAtMs,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (lifecycleState != null) result.lifecycleState = lifecycleState;
    if (lifecycleReason != null) result.lifecycleReason = lifecycleReason;
    if (roles != null) result.roles.addAll(roles);
    if (capabilities != null) result.capabilities.addAll(capabilities);
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    return result;
  }

  Identity._();

  factory Identity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Identity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Identity',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'lifecycleState')
    ..aOS(3, _omitFieldNames ? '' : 'lifecycleReason')
    ..pPS(4, _omitFieldNames ? '' : 'roles')
    ..pPS(5, _omitFieldNames ? '' : 'capabilities')
    ..aInt64(6, _omitFieldNames ? '' : 'createdAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity copyWith(void Function(Identity) updates) =>
      super.copyWith((message) => updates(message as Identity)) as Identity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Identity create() => Identity._();
  @$core.override
  Identity createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Identity getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Identity>(create);
  static Identity? _defaultInstance;

  /// Stable identity id (the Supabase auth.users id / JWT `sub`).
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Lifecycle state: one of "pending", "active", "revoked", "disabled".
  @$pb.TagNumber(2)
  $core.String get lifecycleState => $_getSZ(1);
  @$pb.TagNumber(2)
  set lifecycleState($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLifecycleState() => $_has(1);
  @$pb.TagNumber(2)
  void clearLifecycleState() => $_clearField(2);

  /// Optional human-readable reason for the current lifecycle state.
  @$pb.TagNumber(3)
  $core.String get lifecycleReason => $_getSZ(2);
  @$pb.TagNumber(3)
  set lifecycleReason($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLifecycleReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearLifecycleReason() => $_clearField(3);

  /// Authority roles loaded from the users table (never from the JWT). See RoleAugmentor.
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get roles => $_getList(3);

  /// Fine-grained capabilities, if any. Empty: jZen's authorization model is role-only.
  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get capabilities => $_getList(4);

  /// Creation time in milliseconds since the Unix epoch.
  @$pb.TagNumber(6)
  $fixnum.Int64 get createdAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAtMs() => $_clearField(6);
}

/// POST /api/v1/auth/login request body.
class LoginRequest extends $pb.GeneratedMessage {
  factory LoginRequest({
    $core.String? email,
    $core.String? password,
  }) {
    final result = create();
    if (email != null) result.email = email;
    if (password != null) result.password = password;
    return result;
  }

  LoginRequest._();

  factory LoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest copyWith(void Function(LoginRequest) updates) =>
      super.copyWith((message) => updates(message as LoginRequest))
          as LoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoginRequest create() => LoginRequest._();
  @$core.override
  LoginRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoginRequest>(create);
  static LoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);
}

/// POST /api/v1/auth/register request body.
class RegisterRequest extends $pb.GeneratedMessage {
  factory RegisterRequest({
    $core.String? email,
    $core.String? password,
  }) {
    final result = create();
    if (email != null) result.email = email;
    if (password != null) result.password = password;
    return result;
  }

  RegisterRequest._();

  factory RegisterRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterRequest copyWith(void Function(RegisterRequest) updates) =>
      super.copyWith((message) => updates(message as RegisterRequest))
          as RegisterRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterRequest create() => RegisterRequest._();
  @$core.override
  RegisterRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterRequest>(create);
  static RegisterRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);
}

/// POST /api/v1/auth/restore-password request body. Triggers the Supabase recovery email.
class RestorePasswordRequest extends $pb.GeneratedMessage {
  factory RestorePasswordRequest({
    $core.String? email,
  }) {
    final result = create();
    if (email != null) result.email = email;
    return result;
  }

  RestorePasswordRequest._();

  factory RestorePasswordRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RestorePasswordRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RestorePasswordRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RestorePasswordRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RestorePasswordRequest copyWith(
          void Function(RestorePasswordRequest) updates) =>
      super.copyWith((message) => updates(message as RestorePasswordRequest))
          as RestorePasswordRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestorePasswordRequest create() => RestorePasswordRequest._();
  @$core.override
  RestorePasswordRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RestorePasswordRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RestorePasswordRequest>(create);
  static RestorePasswordRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
