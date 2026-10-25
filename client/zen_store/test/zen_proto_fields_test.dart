import 'package:protobuf/well_known_types/google/protobuf/api.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/type.pb.dart';
import 'package:test/test.dart';
import 'package:zen_store/src/zen_proto_fields.dart';

void main() {
  test('splitting a message by field and joining it again gives the same message', () {
    final api = Api(
      name: 'accounts',
      version: '1.2',
      methods: [
        Method(name: 'list'),
        Method(name: 'get'),
      ],
      options: [Option(name: 'deprecated')],
    );

    final fields = splitFields(api.writeToBuffer());

    expect(fields.keys, unorderedEquals([1, 2, 3, 4]));
    expect(Api.fromBuffer(joinFields(fields)), api);
  });

  test('every occurrence of a repeated field stays with that field, in order', () {
    final api = Api(
      methods: [
        Method(name: 'a'),
        Method(name: 'b'),
        Method(name: 'c'),
      ],
    );

    final methods = Api.fromBuffer(splitFields(api.writeToBuffer())[2]!).methods;

    expect(methods.map((m) => m.name), ['a', 'b', 'c']);
  });

  test('bytes that are not a message are refused', () {
    final whole = Api(name: 'accounts').writeToBuffer();

    expect(() => splitFields(whole.sublist(0, whole.length - 2)), throwsFormatException);
  });
}
