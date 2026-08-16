// This is a generated file - do not edit.
//
// Generated from zen/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Uniform error payload. jZen carries no request/response envelope: HTTP status carries the
/// status, the X-Request-ID header carries the request id, and this message carries the error
/// detail. See docs/architecture/STANDARDS.md "Source of truth" for why every endpoint
/// declares its own typed messages instead of an untyped payload.
class ZenError extends $pb.GeneratedMessage {
  factory ZenError({
    $core.String? code,
    $core.String? message,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? fieldErrors,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (fieldErrors != null) result.fieldErrors.addEntries(fieldErrors);
    return result;
  }

  ZenError._();

  factory ZenError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ZenError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ZenError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'fieldErrors',
        entryClassName: 'ZenError.FieldErrorsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('zen.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZenError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZenError copyWith(void Function(ZenError) updates) =>
      super.copyWith((message) => updates(message as ZenError)) as ZenError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ZenError create() => ZenError._();
  @$core.override
  ZenError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ZenError getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ZenError>(create);
  static ZenError? _defaultInstance;

  /// Machine-readable error code, e.g. "validation", "unauthorized", "not_found".
  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  /// Human-readable message. May be masked in production for 5xx errors.
  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  /// Optional field-level violations, keyed by field path.
  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get fieldErrors => $_getMap(2);
}

/// Standard pagination request parameters for list endpoints.
class PageRequest extends $pb.GeneratedMessage {
  factory PageRequest({
    $core.int? page,
    $core.int? size,
    $core.String? sort,
  }) {
    final result = create();
    if (page != null) result.page = page;
    if (size != null) result.size = size;
    if (sort != null) result.sort = sort;
    return result;
  }

  PageRequest._();

  factory PageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'page')
    ..aI(2, _omitFieldNames ? '' : 'size')
    ..aOS(3, _omitFieldNames ? '' : 'sort')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest copyWith(void Function(PageRequest) updates) =>
      super.copyWith((message) => updates(message as PageRequest))
          as PageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PageRequest create() => PageRequest._();
  @$core.override
  PageRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PageRequest>(create);
  static PageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get page => $_getIZ(0);
  @$pb.TagNumber(1)
  set page($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPage() => $_has(0);
  @$pb.TagNumber(1)
  void clearPage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get size => $_getIZ(1);
  @$pb.TagNumber(2)
  set size($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => $_clearField(2);

  /// Sort spec, e.g. "createdAt desc".
  @$pb.TagNumber(3)
  $core.String get sort => $_getSZ(2);
  @$pb.TagNumber(3)
  set sort($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSort() => $_has(2);
  @$pb.TagNumber(3)
  void clearSort() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
