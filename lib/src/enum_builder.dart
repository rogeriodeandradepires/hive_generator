import 'package:analyzer/dart/element/element.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';

class EnumBuilder extends Builder {
  EnumBuilder(ClassElement cls, List<AdapterField> getters)
      : super(cls, getters, []);

  @override
  String buildRead() {
    var code = StringBuffer();
    code.writeln('switch(reader.readByte()) {');

    for (var field in getters) {
      code.writeln('''
        case ${field.index}:
          return ${cls.displayName}.${field.name};''');
    }

    code.writeln('''
      default:
        throw HiveError('Could not find enum value for byte');
      }''');

    return code.toString();
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('switch(obj) {');

    for (var field in getters) {
      code.writeln('''
        case ${cls.displayName}.${field.name}:
          writer.writeByte(${field.index});
          break;''');
    }

    code.writeln('}');

    return code.toString();
  }
}
