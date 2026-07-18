// This is a generated file - do not edit.
//
// Generated from zen/v1/common.proto.

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

@$core.Deprecated('Use zenErrorDescriptor instead')
const ZenError$json = {
  '1': 'ZenError',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {
      '1': 'field_errors',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.zen.v1.ZenError.FieldErrorsEntry',
      '10': 'fieldErrors'
    },
  ],
  '3': [ZenError_FieldErrorsEntry$json],
};

@$core.Deprecated('Use zenErrorDescriptor instead')
const ZenError_FieldErrorsEntry$json = {
  '1': 'FieldErrorsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ZenError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List zenErrorDescriptor = $convert.base64Decode(
    'CghaZW5FcnJvchISCgRjb2RlGAEgASgJUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2'
    'USRAoMZmllbGRfZXJyb3JzGAMgAygLMiEuemVuLnYxLlplbkVycm9yLkZpZWxkRXJyb3JzRW50'
    'cnlSC2ZpZWxkRXJyb3JzGj4KEEZpZWxkRXJyb3JzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFA'
    'oFdmFsdWUYAiABKAlSBXZhbHVlOgI4AQ==');

@$core.Deprecated('Use pageRequestDescriptor instead')
const PageRequest$json = {
  '1': 'PageRequest',
  '2': [
    {'1': 'page', '3': 1, '4': 1, '5': 5, '10': 'page'},
    {'1': 'size', '3': 2, '4': 1, '5': 5, '10': 'size'},
    {'1': 'sort', '3': 3, '4': 1, '5': 9, '10': 'sort'},
  ],
};

/// Descriptor for `PageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pageRequestDescriptor = $convert.base64Decode(
    'CgtQYWdlUmVxdWVzdBISCgRwYWdlGAEgASgFUgRwYWdlEhIKBHNpemUYAiABKAVSBHNpemUSEg'
    'oEc29ydBgDIAEoCVIEc29ydA==');
