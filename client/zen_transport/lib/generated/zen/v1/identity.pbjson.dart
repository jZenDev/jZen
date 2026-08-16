// This is a generated file - do not edit.
//
// Generated from zen/v1/identity.proto.

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

@$core.Deprecated('Use identityDescriptor instead')
const Identity$json = {
  '1': 'Identity',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'lifecycle_state', '3': 2, '4': 1, '5': 9, '10': 'lifecycleState'},
    {'1': 'lifecycle_reason', '3': 3, '4': 1, '5': 9, '10': 'lifecycleReason'},
    {'1': 'roles', '3': 4, '4': 3, '5': 9, '10': 'roles'},
    {'1': 'capabilities', '3': 5, '4': 3, '5': 9, '10': 'capabilities'},
    {'1': 'created_at_ms', '3': 6, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'email_verified', '3': 7, '4': 1, '5': 8, '10': 'emailVerified'},
  ],
};

/// Descriptor for `Identity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityDescriptor = $convert.base64Decode(
    'CghJZGVudGl0eRIOCgJpZBgBIAEoCVICaWQSJwoPbGlmZWN5Y2xlX3N0YXRlGAIgASgJUg5saW'
    'ZlY3ljbGVTdGF0ZRIpChBsaWZlY3ljbGVfcmVhc29uGAMgASgJUg9saWZlY3ljbGVSZWFzb24S'
    'FAoFcm9sZXMYBCADKAlSBXJvbGVzEiIKDGNhcGFiaWxpdGllcxgFIAMoCVIMY2FwYWJpbGl0aW'
    'VzEiIKDWNyZWF0ZWRfYXRfbXMYBiABKANSC2NyZWF0ZWRBdE1zEiUKDmVtYWlsX3ZlcmlmaWVk'
    'GAcgASgIUg1lbWFpbFZlcmlmaWVk');

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSFAoFZW1haWwYASABKAlSBWVtYWlsEhoKCHBhc3N3b3JkGAIgASgJUg'
    'hwYXNzd29yZA==');

@$core.Deprecated('Use registerRequestDescriptor instead')
const RegisterRequest$json = {
  '1': 'RegisterRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {'1': 'redirect_uri', '3': 3, '4': 1, '5': 9, '10': 'redirectUri'},
  ],
};

/// Descriptor for `RegisterRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerRequestDescriptor = $convert.base64Decode(
    'Cg9SZWdpc3RlclJlcXVlc3QSFAoFZW1haWwYASABKAlSBWVtYWlsEhoKCHBhc3N3b3JkGAIgAS'
    'gJUghwYXNzd29yZBIhCgxyZWRpcmVjdF91cmkYAyABKAlSC3JlZGlyZWN0VXJp');

@$core.Deprecated('Use restorePasswordRequestDescriptor instead')
const RestorePasswordRequest$json = {
  '1': 'RestorePasswordRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'redirect_uri', '3': 2, '4': 1, '5': 9, '10': 'redirectUri'},
  ],
};

/// Descriptor for `RestorePasswordRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restorePasswordRequestDescriptor =
    $convert.base64Decode(
        'ChZSZXN0b3JlUGFzc3dvcmRSZXF1ZXN0EhQKBWVtYWlsGAEgASgJUgVlbWFpbBIhCgxyZWRpcm'
        'VjdF91cmkYAiABKAlSC3JlZGlyZWN0VXJp');

@$core.Deprecated('Use sessionExchangeRequestDescriptor instead')
const SessionExchangeRequest$json = {
  '1': 'SessionExchangeRequest',
  '2': [
    {'1': 'access_token', '3': 1, '4': 1, '5': 9, '10': 'accessToken'},
    {'1': 'refresh_token', '3': 2, '4': 1, '5': 9, '10': 'refreshToken'},
  ],
};

/// Descriptor for `SessionExchangeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionExchangeRequestDescriptor =
    $convert.base64Decode(
        'ChZTZXNzaW9uRXhjaGFuZ2VSZXF1ZXN0EiEKDGFjY2Vzc190b2tlbhgBIAEoCVILYWNjZXNzVG'
        '9rZW4SIwoNcmVmcmVzaF90b2tlbhgCIAEoCVIMcmVmcmVzaFRva2Vu');

@$core.Deprecated('Use setPasswordRequestDescriptor instead')
const SetPasswordRequest$json = {
  '1': 'SetPasswordRequest',
  '2': [
    {'1': 'password', '3': 1, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `SetPasswordRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setPasswordRequestDescriptor =
    $convert.base64Decode(
        'ChJTZXRQYXNzd29yZFJlcXVlc3QSGgoIcGFzc3dvcmQYASABKAlSCHBhc3N3b3Jk');
