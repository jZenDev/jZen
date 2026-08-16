// This is a generated file - do not edit.
//
// Generated from zen/v1/health.proto.

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

@$core.Deprecated('Use healthStatusDescriptor instead')
const HealthStatus$json = {
  '1': 'HealthStatus',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
    {'1': 'service', '3': 2, '4': 1, '5': 9, '10': 'service'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
  ],
};

/// Descriptor for `HealthStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthStatusDescriptor = $convert.base64Decode(
    'CgxIZWFsdGhTdGF0dXMSFgoGc3RhdHVzGAEgASgJUgZzdGF0dXMSGAoHc2VydmljZRgCIAEoCV'
    'IHc2VydmljZRIhCgx0aW1lc3RhbXBfbXMYAyABKANSC3RpbWVzdGFtcE1z');
