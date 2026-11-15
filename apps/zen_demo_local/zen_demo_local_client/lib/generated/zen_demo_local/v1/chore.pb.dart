// This is a generated file - do not edit.
//
// Generated from zen_demo_local/v1/chore.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'chore.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'chore.pbenum.dart';

/// A household chore: the one record zen_demo_local keeps. Four editable fields, each independently
/// editable, so every behaviour of a Local application is one tap away: two devices changing
/// different fields merge, two changing the same field is a conflict the person settles, and a
/// delete against an edit is the other conflict (ADR-065).
///
/// Field numbers are the unit of merging. Never renumber or reuse one.
class Chore extends $pb.GeneratedMessage {
  factory Chore({
    $core.String? id,
    $core.String? title,
    $core.String? note,
    $core.bool? done,
    Priority? priority,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (note != null) result.note = note;
    if (done != null) result.done = done;
    if (priority != null) result.priority = priority;
    return result;
  }

  Chore._();

  factory Chore.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Chore.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Chore',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'zen_demo_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'note')
    ..aOB(4, _omitFieldNames ? '' : 'done')
    ..aE<Priority>(5, _omitFieldNames ? '' : 'priority',
        enumValues: Priority.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chore clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chore copyWith(void Function(Chore) updates) =>
      super.copyWith((message) => updates(message as Chore)) as Chore;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Chore create() => Chore._();
  @$core.override
  Chore createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Chore getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Chore>(create);
  static Chore? _defaultInstance;

  /// The record's key in the store, repeated here because a collection lists values, not ids.
  /// Written once when the chore is made and never edited, so it can never conflict.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get note => $_getSZ(2);
  @$pb.TagNumber(3)
  set note($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNote() => $_has(2);
  @$pb.TagNumber(3)
  void clearNote() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get done => $_getBF(3);
  @$pb.TagNumber(4)
  set done($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDone() => $_has(3);
  @$pb.TagNumber(4)
  void clearDone() => $_clearField(4);

  @$pb.TagNumber(5)
  Priority get priority => $_getN(4);
  @$pb.TagNumber(5)
  set priority(Priority value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPriority() => $_has(4);
  @$pb.TagNumber(5)
  void clearPriority() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
