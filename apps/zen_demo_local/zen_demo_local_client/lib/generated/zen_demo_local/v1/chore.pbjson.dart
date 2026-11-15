// This is a generated file - do not edit.
//
// Generated from zen_demo_local/v1/chore.proto.

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

@$core.Deprecated('Use priorityDescriptor instead')
const Priority$json = {
  '1': 'Priority',
  '2': [
    {'1': 'PRIORITY_NORMAL', '2': 0},
    {'1': 'PRIORITY_LOW', '2': 1},
    {'1': 'PRIORITY_HIGH', '2': 2},
  ],
};

/// Descriptor for `Priority`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List priorityDescriptor = $convert.base64Decode(
    'CghQcmlvcml0eRITCg9QUklPUklUWV9OT1JNQUwQABIQCgxQUklPUklUWV9MT1cQARIRCg1QUk'
    'lPUklUWV9ISUdIEAI=');

@$core.Deprecated('Use choreDescriptor instead')
const Chore$json = {
  '1': 'Chore',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'note', '3': 3, '4': 1, '5': 9, '10': 'note'},
    {'1': 'done', '3': 4, '4': 1, '5': 8, '10': 'done'},
    {
      '1': 'priority',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.zen_demo_local.v1.Priority',
      '10': 'priority'
    },
  ],
};

/// Descriptor for `Chore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List choreDescriptor = $convert.base64Decode(
    'CgVDaG9yZRIOCgJpZBgBIAEoCVICaWQSFAoFdGl0bGUYAiABKAlSBXRpdGxlEhIKBG5vdGUYAy'
    'ABKAlSBG5vdGUSEgoEZG9uZRgEIAEoCFIEZG9uZRI3Cghwcmlvcml0eRgFIAEoDjIbLnplbl9k'
    'ZW1vX2xvY2FsLnYxLlByaW9yaXR5Ughwcmlvcml0eQ==');
