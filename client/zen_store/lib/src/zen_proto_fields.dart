import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

/// Splits a serialized proto message into its top-level fields, keyed by field number, each the
/// exact bytes that field occupies on the wire (every occurrence of a repeated field, in order).
///
/// This is what lets two devices' edits to *different* fields of one record merge on their own:
/// the store compares and versions each field separately. It works on wire bytes, so it needs no
/// knowledge of the message type, and joining the parts back ([joinFields]) yields a message
/// equal to the original — protobuf defines the concatenation of encodings as their merge.
///
/// Throws a [FormatException] for bytes that are not a proto message, and for groups, which
/// proto3 does not have.
@internal
Map<int, Uint8List> splitFields(Uint8List bytes) {
  final parts = <int, BytesBuilder>{};
  var offset = 0;
  while (offset < bytes.length) {
    final start = offset;
    final (tag, afterTag) = _varint(bytes, offset);
    offset = afterTag;
    final field = tag >> 3;
    if (field == 0) throw const FormatException('field number 0 is not valid');
    switch (tag & 7) {
      case 0:
        offset = _varint(bytes, offset).$2;
      case 1:
        offset += 8;
      case 2:
        final (length, afterLength) = _varint(bytes, offset);
        offset = afterLength + length;
      case 5:
        offset += 4;
      default:
        throw FormatException('wire type ${tag & 7} of field $field is not supported');
    }
    if (offset > bytes.length) throw FormatException('field $field runs past the message');
    parts.putIfAbsent(field, BytesBuilder.new).add(Uint8List.sublistView(bytes, start, offset));
  }
  return {for (final entry in parts.entries) entry.key: entry.value.takeBytes()};
}

/// Which fields of a message are declared `optional` in the `.proto`, so keep explicit presence
/// ([ZenStore.collection]'s `explicitPresence`): [fields] are field numbers of the message itself,
/// and [messages] maps a message-typed field to the declaration for the message it holds, which is
/// how a nested `optional` field is named.
///
/// `const ZenPresence({2})` is field 2; `{8: ZenPresence({2})}` names field 2 inside the message
/// field 8, and nests further the same way.
final class ZenPresence {
  /// No field is declared explicit.
  static const ZenPresence none = ZenPresence({});

  /// Numbers of the fields of this message that are `optional`.
  final Set<int> fields;

  /// For a message field of this message, the declaration for the message inside it.
  final Map<int, ZenPresence> messages;

  /// Declares [fields] explicit, and [messages] for what is inside message fields.
  const ZenPresence(this.fields, [this.messages = const {}]);

  /// Throws an [ArgumentError] unless every declared field exists in [info], and every key of
  /// [messages] is a singular message field whose own declaration holds for its type. [path] names
  /// where [info] sits, for the message.
  @internal
  void validate(BuilderInfo info, [String path = '']) {
    for (final tag in fields) {
      if (info.fieldInfo[tag] == null) {
        throw ArgumentError.value(
          tag,
          'explicitPresence',
          'the message ${info.qualifiedMessageName}$path has no field $tag',
        );
      }
    }
    for (final MapEntry(key: tag, value: inner) in messages.entries) {
      final field = info.fieldInfo[tag];
      final nested = field?.subBuilder;
      if (field == null || nested == null || field.isRepeated || field.isMapField) {
        throw ArgumentError.value(
          tag,
          'explicitPresence',
          'field $tag of ${info.qualifiedMessageName}$path is not a singular message field, so '
              'nothing can be declared inside it',
        );
      }
      inner.validate(nested().info_, '$path.${field.name}');
    }
  }

  /// This declaration with [other]'s added.
  ZenPresence merge(ZenPresence other) => ZenPresence(
    {...fields, ...other.fields},
    {
      ...messages,
      for (final MapEntry(:key, :value) in other.messages.entries)
        key: messages[key]?.merge(value) ?? value,
    },
  );

  @override
  bool operator ==(Object other) =>
      other is ZenPresence &&
      other.fields.length == fields.length &&
      other.fields.containsAll(fields) &&
      other.messages.length == messages.length &&
      messages.entries.every((e) => other.messages[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(fields),
    Object.hashAllUnordered(messages.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

/// [splitFields] of [message], with proto3 implicit presence applied: a field that is a plain
/// scalar or an enum, neither repeated nor a map, and not declared in [explicitPresence], is left
/// out when its value is its type's default. The rule applies inside a singular message field too,
/// to that nested message's own fields (the nested bytes are rewritten without them); a message
/// held in a repeated or map field is kept as it is.
///
/// The Dart runtime writes such a field when it was assigned its default (`description = ''`)
/// though proto3 defines that as the same value as never setting it, so two devices clearing one
/// field in two ways would otherwise see two different values — a conflict about nothing — and a
/// message rebuilt from another type would count fields it never meant to touch as edits.
/// [explicitPresence] names the fields declared `optional` in the `.proto` (a message field is
/// always explicit): the runtime cannot tell them apart, and for those "set to the default" and
/// "unset" are different values that must stay different.
@internal
Map<int, Uint8List> splitMessage(GeneratedMessage message, ZenPresence explicitPresence) {
  final fields = splitFields(message.writeToBuffer());
  for (final info in message.info_.fieldInfo.values) {
    final tag = info.tagNumber;
    // A oneof member has presence of its own: `kind_int = 0` is a choice, not an absence.
    if (!fields.containsKey(tag) || info.isRepeated || info.isMapField) continue;
    if (PbFieldType.isGroupOrMessage(info.type)) {
      if (message.getField(tag) case final GeneratedMessage nested) {
        fields[tag] = _lengthDelimited(
          tag,
          joinFields(splitMessage(nested, explicitPresence.messages[tag] ?? ZenPresence.none)),
        );
      }
      continue;
    }
    if (explicitPresence.fields.contains(tag) || message.info_.oneofs.containsKey(tag)) continue;
    if (_isDefault(message.getField(tag))) fields.remove(tag);
  }
  return fields;
}

Uint8List _lengthDelimited(int tag, Uint8List body) {
  final out = BytesBuilder(copy: false);
  void varint(int value) {
    while (value > 0x7f) {
      out.addByte((value & 0x7f) | 0x80);
      value >>= 7;
    }
    out.addByte(value);
  }

  varint((tag << 3) | 2);
  varint(body.length);
  out.add(body);
  return out.takeBytes();
}

bool _isDefault(Object? value) => switch (value) {
  null => true,
  String() => value.isEmpty,
  List<int>() => value.isEmpty,
  bool() => !value,
  int() => value == 0,
  // -0.0 is not the default: proto3 writes it, and it reads back as -0.0.
  double() => value == 0 && !value.isNegative,
  ProtobufEnum() => value.value == 0,
  // Int64 and Uint64 (package:fixnum), which `protobuf` does not export by name.
  _ => value.toString() == '0',
};

/// The message whose fields are [fields], in field-number order.
@internal
Uint8List joinFields(Map<int, Uint8List> fields) {
  final builder = BytesBuilder(copy: false);
  for (final field in fields.keys.toList()..sort()) {
    builder.add(fields[field]!);
  }
  return builder.takeBytes();
}

(int, int) _varint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (true) {
    if (offset >= bytes.length) throw const FormatException('a varint runs past the message');
    if (shift > 63) throw const FormatException('a varint is longer than 10 bytes');
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) return (value, offset);
    shift += 7;
  }
}
