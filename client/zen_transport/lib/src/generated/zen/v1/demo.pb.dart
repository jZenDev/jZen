// This is a generated file - do not edit.
//
// Generated from zen/v1/demo.proto.

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

/// GET /api/v1/demo/ping response. A liveness probe that returns a message localized from the
/// request's Accept-Language (supported {en, uk}), demonstrating server-side localization and
/// both transport modes. Maps to DartZen's PingContract (message + timestamp).
class Ping extends $pb.GeneratedMessage {
  factory Ping({
    $core.String? message,
    $fixnum.Int64? timestampMs,
  }) {
    final result = create();
    if (message != null) result.message = message;
    if (timestampMs != null) result.timestampMs = timestampMs;
    return result;
  }

  Ping._();

  factory Ping.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ping.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ping',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping copyWith(void Function(Ping) updates) =>
      super.copyWith((message) => updates(message as Ping)) as Ping;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ping create() => Ping._();
  @$core.override
  Ping createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ping getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ping>(create);
  static Ping? _defaultInstance;

  /// Localized "server is alive" message, rendered from DemoMessages for the request locale.
  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  /// Server wall-clock time in milliseconds since the Unix epoch.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);
}

/// GET /api/v1/demo/terms response. Localized Markdown terms content, selected by the
/// request's Accept-Language. Maps to DartZen's TermsContract (content + content_type).
class Terms extends $pb.GeneratedMessage {
  factory Terms({
    $core.String? content,
    $core.String? contentType,
  }) {
    final result = create();
    if (content != null) result.content = content;
    if (contentType != null) result.contentType = contentType;
    return result;
  }

  Terms._();

  factory Terms.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Terms.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Terms',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'content')
    ..aOS(2, _omitFieldNames ? '' : 'contentType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Terms clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Terms copyWith(void Function(Terms) updates) =>
      super.copyWith((message) => updates(message as Terms)) as Terms;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Terms create() => Terms._();
  @$core.override
  Terms createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Terms getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Terms>(create);
  static Terms? _defaultInstance;

  /// Markdown document body for the requested locale.
  @$pb.TagNumber(1)
  $core.String get content => $_getSZ(0);
  @$pb.TagNumber(1)
  set content($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => $_clearField(1);

  /// MIME type of `content`; the demo serves "text/markdown".
  @$pb.TagNumber(2)
  $core.String get contentType => $_getSZ(1);
  @$pb.TagNumber(2)
  set contentType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContentType() => $_has(1);
  @$pb.TagNumber(2)
  void clearContentType() => $_clearField(2);
}

/// GET /api/v1/demo/profile response. The authenticated user's demo profile, resolved from the
/// session cookie (SmallRye JWT reads zen_access_token); returns a ZenError 401 when anonymous.
/// Maps to DartZen's ProfileContract (user_id, display_name, email, bio).
class DemoProfile extends $pb.GeneratedMessage {
  factory DemoProfile({
    $core.String? userId,
    $core.String? displayName,
    $core.String? email,
    $core.String? bio,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (displayName != null) result.displayName = displayName;
    if (email != null) result.email = email;
    if (bio != null) result.bio = bio;
    return result;
  }

  DemoProfile._();

  factory DemoProfile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DemoProfile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DemoProfile',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'bio')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DemoProfile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DemoProfile copyWith(void Function(DemoProfile) updates) =>
      super.copyWith((message) => updates(message as DemoProfile))
          as DemoProfile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DemoProfile create() => DemoProfile._();
  @$core.override
  DemoProfile createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DemoProfile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DemoProfile>(create);
  static DemoProfile? _defaultInstance;

  /// Stable user id (the Supabase auth.users id / JWT `sub`).
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  /// Display name for the profile view.
  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  /// Account email.
  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  /// Optional free-text biography.
  @$pb.TagNumber(4)
  $core.String get bio => $_getSZ(3);
  @$pb.TagNumber(4)
  set bio($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBio() => $_has(3);
  @$pb.TagNumber(4)
  void clearBio() => $_clearField(4);
}

/// Bidirectional frame for the /api/v1/demo/ws echo endpoint. Maps to DartZen's
/// WebSocketMessageContract. The client sends type "message"; the server echoes it back as
/// type "echo", or replies type "error" on a decode failure. zen_demo forces the protobuf
/// binary format for the socket, so both platforms send binary frames.
class WebSocketMessage extends $pb.GeneratedMessage {
  factory WebSocketMessage({
    $core.String? type,
    $core.String? payload,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (payload != null) result.payload = payload;
    return result;
  }

  WebSocketMessage._();

  factory WebSocketMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WebSocketMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WebSocketMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'type')
    ..aOS(2, _omitFieldNames ? '' : 'payload')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebSocketMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebSocketMessage copyWith(void Function(WebSocketMessage) updates) =>
      super.copyWith((message) => updates(message as WebSocketMessage))
          as WebSocketMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WebSocketMessage create() => WebSocketMessage._();
  @$core.override
  WebSocketMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WebSocketMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WebSocketMessage>(create);
  static WebSocketMessage? _defaultInstance;

  /// Frame kind: "message" (client -> server), "echo" / "error" (server -> client).
  @$pb.TagNumber(1)
  $core.String get type => $_getSZ(0);
  @$pb.TagNumber(1)
  set type($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  /// Opaque payload string carried by the frame.
  @$pb.TagNumber(2)
  $core.String get payload => $_getSZ(1);
  @$pb.TagNumber(2)
  set payload($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
