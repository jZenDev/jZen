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

class Priority extends $pb.ProtobufEnum {
  static const Priority PRIORITY_NORMAL =
      Priority._(0, _omitEnumNames ? '' : 'PRIORITY_NORMAL');
  static const Priority PRIORITY_LOW =
      Priority._(1, _omitEnumNames ? '' : 'PRIORITY_LOW');
  static const Priority PRIORITY_HIGH =
      Priority._(2, _omitEnumNames ? '' : 'PRIORITY_HIGH');

  static const $core.List<Priority> values = <Priority>[
    PRIORITY_NORMAL,
    PRIORITY_LOW,
    PRIORITY_HIGH,
  ];

  static final $core.List<Priority?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Priority? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Priority._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
