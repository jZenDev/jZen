// This is a generated file - do not edit.
//
// Generated from zen/v1/admin.proto.

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

@$core.Deprecated('Use adminUserDescriptor instead')
const AdminUser$json = {
  '1': 'AdminUser',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'email', '3': 2, '4': 1, '5': 9, '10': 'email'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'nickname', '3': 4, '4': 1, '5': 9, '10': 'nickname'},
    {'1': 'role', '3': 5, '4': 1, '5': 9, '10': 'role'},
    {'1': 'language', '3': 6, '4': 1, '5': 9, '10': 'language'},
    {'1': 'is_premium', '3': 7, '4': 1, '5': 8, '10': 'isPremium'},
    {'1': 'is_private', '3': 8, '4': 1, '5': 8, '10': 'isPrivate'},
    {'1': 'email_verified', '3': 9, '4': 1, '5': 8, '10': 'emailVerified'},
    {'1': 'created_at_ms', '3': 10, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'last_login_at_ms', '3': 11, '4': 1, '5': 3, '10': 'lastLoginAtMs'},
  ],
};

/// Descriptor for `AdminUser`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List adminUserDescriptor = $convert.base64Decode(
    'CglBZG1pblVzZXISDgoCaWQYASABKAlSAmlkEhQKBWVtYWlsGAIgASgJUgVlbWFpbBIhCgxkaX'
    'NwbGF5X25hbWUYAyABKAlSC2Rpc3BsYXlOYW1lEhoKCG5pY2tuYW1lGAQgASgJUghuaWNrbmFt'
    'ZRISCgRyb2xlGAUgASgJUgRyb2xlEhoKCGxhbmd1YWdlGAYgASgJUghsYW5ndWFnZRIdCgppc1'
    '9wcmVtaXVtGAcgASgIUglpc1ByZW1pdW0SHQoKaXNfcHJpdmF0ZRgIIAEoCFIJaXNQcml2YXRl'
    'EiUKDmVtYWlsX3ZlcmlmaWVkGAkgASgIUg1lbWFpbFZlcmlmaWVkEiIKDWNyZWF0ZWRfYXRfbX'
    'MYCiABKANSC2NyZWF0ZWRBdE1zEicKEGxhc3RfbG9naW5fYXRfbXMYCyABKANSDWxhc3RMb2dp'
    'bkF0TXM=');
