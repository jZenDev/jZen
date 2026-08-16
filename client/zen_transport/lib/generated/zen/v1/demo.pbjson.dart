// This is a generated file - do not edit.
//
// Generated from zen/v1/demo.proto.

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

@$core.Deprecated('Use pingDescriptor instead')
const Ping$json = {
  '1': 'Ping',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 9, '10': 'message'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
  ],
};

/// Descriptor for `Ping`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingDescriptor = $convert.base64Decode(
    'CgRQaW5nEhgKB21lc3NhZ2UYASABKAlSB21lc3NhZ2USIQoMdGltZXN0YW1wX21zGAIgASgDUg'
    't0aW1lc3RhbXBNcw==');

@$core.Deprecated('Use termsDescriptor instead')
const Terms$json = {
  '1': 'Terms',
  '2': [
    {'1': 'content', '3': 1, '4': 1, '5': 9, '10': 'content'},
    {'1': 'content_type', '3': 2, '4': 1, '5': 9, '10': 'contentType'},
  ],
};

/// Descriptor for `Terms`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List termsDescriptor = $convert.base64Decode(
    'CgVUZXJtcxIYCgdjb250ZW50GAEgASgJUgdjb250ZW50EiEKDGNvbnRlbnRfdHlwZRgCIAEoCV'
    'ILY29udGVudFR5cGU=');

@$core.Deprecated('Use demoProfileDescriptor instead')
const DemoProfile$json = {
  '1': 'DemoProfile',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'email', '3': 3, '4': 1, '5': 9, '10': 'email'},
    {'1': 'bio', '3': 4, '4': 1, '5': 9, '10': 'bio'},
  ],
};

/// Descriptor for `DemoProfile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List demoProfileDescriptor = $convert.base64Decode(
    'CgtEZW1vUHJvZmlsZRIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSIQoMZGlzcGxheV9uYW1lGA'
    'IgASgJUgtkaXNwbGF5TmFtZRIUCgVlbWFpbBgDIAEoCVIFZW1haWwSEAoDYmlvGAQgASgJUgNi'
    'aW8=');

@$core.Deprecated('Use webSocketMessageDescriptor instead')
const WebSocketMessage$json = {
  '1': 'WebSocketMessage',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 9, '10': 'type'},
    {'1': 'payload', '3': 2, '4': 1, '5': 9, '10': 'payload'},
  ],
};

/// Descriptor for `WebSocketMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List webSocketMessageDescriptor = $convert.base64Decode(
    'ChBXZWJTb2NrZXRNZXNzYWdlEhIKBHR5cGUYASABKAlSBHR5cGUSGAoHcGF5bG9hZBgCIAEoCV'
    'IHcGF5bG9hZA==');
