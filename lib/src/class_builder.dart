import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

class ClassBuilder extends Builder {
  // Helper to get constructor parameters for all analyzer versions
  Iterable<dynamic> _getConstructorParameters(ConstructorElement constr) {
    // Fallback for analyzer versions without .parameters or ParameterElement
    return constr.children.where((e) => e.kind.name == 'PARAMETER');
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments[0];
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var cast = '';
      if (listChecker.isExactlyType(type)) {
        cast = '?.toList()';
      } else if (setChecker.isExactlyType(type)) {
        cast = '?.toSet()';
      }
      return '?.map((dynamic e)=> ${_cast(arg, 'e')})$cast';
    } else {
      return '?.cast<${arg.getDisplayString(withNullability: false)}>()';
    }
  }

  String _castMap(DartType type) {
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '?.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '?.cast<${arg1.getDisplayString(withNullability: false)}, '
      '${arg2.getDisplayString(withNullability: false)}>()';
    }
  }

  bool isMapOrIterable(DartType type) {
    return listChecker.isExactlyType(type) ||
        setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type) ||
        mapChecker.isExactlyType(type);
  }

  final hiveListChecker =
      const TypeChecker.fromUrl('package:hive/hive.dart#HiveList');
  final listChecker = const TypeChecker.fromUrl('dart:core#List');
  final mapChecker = const TypeChecker.fromUrl('dart:core#Map');
  final setChecker = const TypeChecker.fromUrl('dart:core#Set');
  final iterableChecker = const TypeChecker.fromUrl('dart:core#Iterable');
  final uint8ListChecker =
      const TypeChecker.fromUrl('dart:typed_data#Uint8List');

  ClassBuilder(super.cls, super.getters, super.setters);

  String _cast(DartType type, String variable) {
    if (hiveListChecker.isExactlyType(type)) {
      return '($variable as HiveList)?.castHiveList()';
    } else if (iterableChecker.isAssignableFromType(type) &&
        !isUint8List(type)) {
      return '($variable as List)${_castIterable(type)}';
    } else if (mapChecker.isExactlyType(type)) {
      return '($variable as Map)${_castMap(type)}';
    } else {
      return '$variable as ${type.getDisplayString(withNullability: false)}';
    }
  }

  @override
  String buildRead() {
    var code = StringBuffer();
    code.writeln('var numOfFields = reader.readByte();');
    code.writeln('var fields = <int, dynamic>{');
    code.writeln(
        // ignore: lines_longer_than_80_chars
        '  for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),');
    code.writeln('};');
    code.write('return ${cls.name}(');

    // Find unnamed constructor safely
    ConstructorElement? constr;
    for (var c in cls.constructors) {
      if (c.name == '') {
        constr = c;
        break;
      }
    }
    check(constr != null, 'Provide an unnamed constructor.');

    // The remaining fields to initialize.
    var fieldsList = setters.toList();

    var initializingParams = _getConstructorParameters(constr!)
        .where((param) => param.isInitializingFormal == true);
    for (var param in initializingParams) {
      AdapterField field;
      try {
        field = fieldsList.firstWhere((it) => it.name == param.name);
      } catch (_) {
        field = getters.firstWhere((it) => it.name == param.name);
      }
      if (param.isNamed) {
        code.write('${param.name}: ');
      }
      code.write('${_cast(param.type, 'fields[${field.index}]')}, ');
      fieldsList.remove(field);
    }
    code.write(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var field in fieldsList) {
      code.write(
          '..${field.name} = ${_cast(field.type, 'fields[${field.index}]')}');
    }

    code.writeln(';');
    return code.toString();
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${getters.length})');
    for (var field in getters) {
      var value = _convertIterable(field.type, 'obj.${field.name}');
      code.writeln('''
      ..writeByte(${field.index})
      ..write($value)''');
    }
    code.writeln(';');
    return code.toString();
  }

  String _convertIterable(DartType type, String accessor) {
    if (setChecker.isExactlyType(type) || iterableChecker.isExactlyType(type)) {
      return '$accessor?.toList()';
    } else {
      return accessor;
    }
  }
}
