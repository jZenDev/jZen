// This is a generated file - do not edit.
//
// Generated from zen/v1/admin.proto.

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

/// A user row projected for administration. Unlike Identity (the session payload), this exposes
/// the management-relevant columns of the users table: contact, role, and the product/GDPR flags
/// an admin edits. `id` is the Supabase auth.users id (the react-admin record id). Timestamps are
/// epoch milliseconds, matching the `*_ms` convention in identity.proto.
class AdminUser extends $pb.GeneratedMessage {
  factory AdminUser({
    $core.String? id,
    $core.String? email,
    $core.String? displayName,
    $core.String? nickname,
    $core.String? role,
    $core.String? language,
    $core.bool? isPremium,
    $core.bool? isPrivate,
    $core.bool? emailVerified,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? lastLoginAtMs,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (email != null) result.email = email;
    if (displayName != null) result.displayName = displayName;
    if (nickname != null) result.nickname = nickname;
    if (role != null) result.role = role;
    if (language != null) result.language = language;
    if (isPremium != null) result.isPremium = isPremium;
    if (isPrivate != null) result.isPrivate = isPrivate;
    if (emailVerified != null) result.emailVerified = emailVerified;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (lastLoginAtMs != null) result.lastLoginAtMs = lastLoginAtMs;
    return result;
  }

  AdminUser._();

  factory AdminUser.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminUser.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminUser',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'email')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'nickname')
    ..aOS(5, _omitFieldNames ? '' : 'role')
    ..aOS(6, _omitFieldNames ? '' : 'language')
    ..aOB(7, _omitFieldNames ? '' : 'isPremium')
    ..aOB(8, _omitFieldNames ? '' : 'isPrivate')
    ..aOB(9, _omitFieldNames ? '' : 'emailVerified')
    ..aInt64(10, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(11, _omitFieldNames ? '' : 'lastLoginAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminUser clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminUser copyWith(void Function(AdminUser) updates) =>
      super.copyWith((message) => updates(message as AdminUser)) as AdminUser;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminUser create() => AdminUser._();
  @$core.override
  AdminUser createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminUser getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AdminUser>(create);
  static AdminUser? _defaultInstance;

  /// Stable user id (the Supabase auth.users id / JWT `sub`); the react-admin record id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Account email (users.email, NOT NULL).
  @$pb.TagNumber(2)
  $core.String get email => $_getSZ(1);
  @$pb.TagNumber(2)
  set email($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmail() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmail() => $_clearField(2);

  /// Display name, if set.
  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set displayName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisplayName() => $_clearField(3);

  /// Handle / nickname, if set.
  @$pb.TagNumber(4)
  $core.String get nickname => $_getSZ(3);
  @$pb.TagNumber(4)
  set nickname($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNickname() => $_has(3);
  @$pb.TagNumber(4)
  void clearNickname() => $_clearField(4);

  /// Authority role: one of "user", "admin", "reviewer", "b2b_admin".
  @$pb.TagNumber(5)
  $core.String get role => $_getSZ(4);
  @$pb.TagNumber(5)
  set role($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRole() => $_has(4);
  @$pb.TagNumber(5)
  void clearRole() => $_clearField(5);

  /// Preferred language code (feeds i18n and localized email), e.g. "en".
  @$pb.TagNumber(6)
  $core.String get language => $_getSZ(5);
  @$pb.TagNumber(6)
  set language($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLanguage() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanguage() => $_clearField(6);

  /// Payment flag: whether the account is premium.
  @$pb.TagNumber(7)
  $core.bool get isPremium => $_getBF(6);
  @$pb.TagNumber(7)
  set isPremium($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsPremium() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsPremium() => $_clearField(7);

  /// Privacy flag: whether the profile is private.
  @$pb.TagNumber(8)
  $core.bool get isPrivate => $_getBF(7);
  @$pb.TagNumber(8)
  set isPrivate($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIsPrivate() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsPrivate() => $_clearField(8);

  /// Whether the account email is verified.
  @$pb.TagNumber(9)
  $core.bool get emailVerified => $_getBF(8);
  @$pb.TagNumber(9)
  set emailVerified($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasEmailVerified() => $_has(8);
  @$pb.TagNumber(9)
  void clearEmailVerified() => $_clearField(9);

  /// Account creation time in milliseconds since the Unix epoch.
  @$pb.TagNumber(10)
  $fixnum.Int64 get createdAtMs => $_getI64(9);
  @$pb.TagNumber(10)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCreatedAtMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedAtMs() => $_clearField(10);

  /// Last login time in milliseconds since the Unix epoch; 0 when the user never logged in.
  @$pb.TagNumber(11)
  $fixnum.Int64 get lastLoginAtMs => $_getI64(10);
  @$pb.TagNumber(11)
  set lastLoginAtMs($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLastLoginAtMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearLastLoginAtMs() => $_clearField(11);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
