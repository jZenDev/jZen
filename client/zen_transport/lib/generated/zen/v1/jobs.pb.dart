// This is a generated file - do not edit.
//
// Generated from zen/v1/jobs.proto.

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

/// The outcome of a single job executed during one tick.
class JobRun extends $pb.GeneratedMessage {
  factory JobRun({
    $core.String? jobId,
    $core.String? status,
    $fixnum.Int64? startedAtMs,
    $fixnum.Int64? durationMs,
    $core.String? error,
  }) {
    final result = create();
    if (jobId != null) result.jobId = jobId;
    if (status != null) result.status = status;
    if (startedAtMs != null) result.startedAtMs = startedAtMs;
    if (durationMs != null) result.durationMs = durationMs;
    if (error != null) result.error = error;
    return result;
  }

  JobRun._();

  factory JobRun.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory JobRun.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobRun',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'jobId')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..aInt64(3, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(4, _omitFieldNames ? '' : 'durationMs')
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobRun clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobRun copyWith(void Function(JobRun) updates) =>
      super.copyWith((message) => updates(message as JobRun)) as JobRun;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JobRun create() => JobRun._();
  @$core.override
  JobRun createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static JobRun getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JobRun>(create);
  static JobRun? _defaultInstance;

  /// Stable job id, matching the registered ZenJob and the zen_jobs primary key.
  @$pb.TagNumber(1)
  $core.String get jobId => $_getSZ(0);
  @$pb.TagNumber(1)
  set jobId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  /// Terminal status of this run: "success" or "failure".
  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  /// When this run started, in milliseconds since the Unix epoch.
  @$pb.TagNumber(3)
  $fixnum.Int64 get startedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set startedAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartedAtMs() => $_clearField(3);

  /// How long the run took, in milliseconds.
  @$pb.TagNumber(4)
  $fixnum.Int64 get durationMs => $_getI64(3);
  @$pb.TagNumber(4)
  set durationMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => $_clearField(4);

  /// Failure detail; empty on success.
  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
}

/// The result of one master tick: what was due and what happened to it.
class JobTickResult extends $pb.GeneratedMessage {
  factory JobTickResult({
    $fixnum.Int64? startedAtMs,
    $core.int? due,
    $core.int? succeeded,
    $core.int? failed,
    $core.bool? skippedOverlap,
    $core.Iterable<JobRun>? runs,
  }) {
    final result = create();
    if (startedAtMs != null) result.startedAtMs = startedAtMs;
    if (due != null) result.due = due;
    if (succeeded != null) result.succeeded = succeeded;
    if (failed != null) result.failed = failed;
    if (skippedOverlap != null) result.skippedOverlap = skippedOverlap;
    if (runs != null) result.runs.addAll(runs);
    return result;
  }

  JobTickResult._();

  factory JobTickResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory JobTickResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobTickResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'zen.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'startedAtMs')
    ..aI(2, _omitFieldNames ? '' : 'due')
    ..aI(3, _omitFieldNames ? '' : 'succeeded')
    ..aI(4, _omitFieldNames ? '' : 'failed')
    ..aOB(5, _omitFieldNames ? '' : 'skippedOverlap')
    ..pPM<JobRun>(6, _omitFieldNames ? '' : 'runs', subBuilder: JobRun.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobTickResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobTickResult copyWith(void Function(JobTickResult) updates) =>
      super.copyWith((message) => updates(message as JobTickResult))
          as JobTickResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JobTickResult create() => JobTickResult._();
  @$core.override
  JobTickResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static JobTickResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JobTickResult>(create);
  static JobTickResult? _defaultInstance;

  /// When the tick started, in milliseconds since the Unix epoch.
  @$pb.TagNumber(1)
  $fixnum.Int64 get startedAtMs => $_getI64(0);
  @$pb.TagNumber(1)
  set startedAtMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStartedAtMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartedAtMs() => $_clearField(1);

  /// How many enabled, registered jobs were due at that moment.
  @$pb.TagNumber(2)
  $core.int get due => $_getIZ(1);
  @$pb.TagNumber(2)
  set due($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDue() => $_has(1);
  @$pb.TagNumber(2)
  void clearDue() => $_clearField(2);

  /// How many due jobs completed without throwing.
  @$pb.TagNumber(3)
  $core.int get succeeded => $_getIZ(2);
  @$pb.TagNumber(3)
  set succeeded($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSucceeded() => $_has(2);
  @$pb.TagNumber(3)
  void clearSucceeded() => $_clearField(3);

  /// How many due jobs threw.
  @$pb.TagNumber(4)
  $core.int get failed => $_getIZ(3);
  @$pb.TagNumber(4)
  set failed($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFailed() => $_has(3);
  @$pb.TagNumber(4)
  void clearFailed() => $_clearField(4);

  /// True when a tick was already running and this one did nothing (the overlap guard).
  @$pb.TagNumber(5)
  $core.bool get skippedOverlap => $_getBF(4);
  @$pb.TagNumber(5)
  set skippedOverlap($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSkippedOverlap() => $_has(4);
  @$pb.TagNumber(5)
  void clearSkippedOverlap() => $_clearField(5);

  /// One entry per job actually executed, in execution order.
  @$pb.TagNumber(6)
  $pb.PbList<JobRun> get runs => $_getList(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
