// This is a generated file - do not edit.
//
// Generated from zen/v1/jobs.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use jobRunDescriptor instead')
const JobRun$json = {
  '1': 'JobRun',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 9, '10': 'jobId'},
    {'1': 'status', '3': 2, '4': 1, '5': 9, '10': 'status'},
    {'1': 'started_at_ms', '3': 3, '4': 1, '5': 3, '10': 'startedAtMs'},
    {'1': 'duration_ms', '3': 4, '4': 1, '5': 3, '10': 'durationMs'},
    {'1': 'error', '3': 5, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `JobRun`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobRunDescriptor = $convert.base64Decode(
    'CgZKb2JSdW4SFQoGam9iX2lkGAEgASgJUgVqb2JJZBIWCgZzdGF0dXMYAiABKAlSBnN0YXR1cx'
    'IiCg1zdGFydGVkX2F0X21zGAMgASgDUgtzdGFydGVkQXRNcxIfCgtkdXJhdGlvbl9tcxgEIAEo'
    'A1IKZHVyYXRpb25NcxIUCgVlcnJvchgFIAEoCVIFZXJyb3I=');

@$core.Deprecated('Use jobTickResultDescriptor instead')
const JobTickResult$json = {
  '1': 'JobTickResult',
  '2': [
    {'1': 'started_at_ms', '3': 1, '4': 1, '5': 3, '10': 'startedAtMs'},
    {'1': 'due', '3': 2, '4': 1, '5': 5, '10': 'due'},
    {'1': 'succeeded', '3': 3, '4': 1, '5': 5, '10': 'succeeded'},
    {'1': 'failed', '3': 4, '4': 1, '5': 5, '10': 'failed'},
    {'1': 'skipped_overlap', '3': 5, '4': 1, '5': 8, '10': 'skippedOverlap'},
    {'1': 'runs', '3': 6, '4': 3, '5': 11, '6': '.zen.v1.JobRun', '10': 'runs'},
  ],
};

/// Descriptor for `JobTickResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobTickResultDescriptor = $convert.base64Decode(
    'Cg1Kb2JUaWNrUmVzdWx0EiIKDXN0YXJ0ZWRfYXRfbXMYASABKANSC3N0YXJ0ZWRBdE1zEhAKA2'
    'R1ZRgCIAEoBVIDZHVlEhwKCXN1Y2NlZWRlZBgDIAEoBVIJc3VjY2VlZGVkEhYKBmZhaWxlZBgE'
    'IAEoBVIGZmFpbGVkEicKD3NraXBwZWRfb3ZlcmxhcBgFIAEoCFIOc2tpcHBlZE92ZXJsYXASIg'
    'oEcnVucxgGIAMoCzIOLnplbi52MS5Kb2JSdW5SBHJ1bnM=');
