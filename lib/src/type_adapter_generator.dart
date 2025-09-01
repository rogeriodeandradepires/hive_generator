import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/class_builder.dart';
import 'package:hive_generator/src/enum_builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

class TypeAdapterGenerator extends GeneratorForAnnotation<HiveType> {
  @override
  Future<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) async {
    var cls = getClass(element);
    var library = await buildStep.inputLibrary;
    var gettersAndSetters = getAccessors(cls, library);

    var getters = gettersAndSetters[0];
    verifyFieldIndices(getters);

    var setters = gettersAndSetters[1];
    verifyFieldIndices(setters);

    var typeId = getTypeId(annotation);

    var adapterName = getAdapterName(cls.displayName, annotation);
    var builder = element is EnumElement
        ? EnumBuilder(cls, getters)
        : ClassBuilder(cls, getters, setters);

    return '''
    class $adapterName extends TypeAdapter<${cls.displayName}> {
      @override
      final int typeId = $typeId;

      @override
      ${cls.displayName} read(BinaryReader reader) {
        ${builder.buildRead()}
      }

      @override
      void write(BinaryWriter writer, ${cls.displayName} obj) {
        ${builder.buildWrite()}
      }
    }
    ''';
  }

  ClassElement getClass(Element element) {
    check(element is ClassElement,
        'Only classes or enums are allowed to be annotated with @HiveType.');
    return element as ClassElement;
  }

  Set<String> getAllAccessorNames(ClassElement cls) {
    var accessorNames = <String>{};
    var supertypes =
        cls.allSupertypes.map((it) => it.element).whereType<ClassElement>();
    for (var type in [cls, ...supertypes]) {
      for (var field in type.fields) {
        if (!field.isStatic && field.name != null) {
          accessorNames.add(field.name!);
        }
      }
    }
    return accessorNames;
  }

  List<List<AdapterField>> getAccessors(
      ClassElement cls, LibraryElement library) {
    var accessorNames = getAllAccessorNames(cls);

    var getters = <AdapterField>[];
    var setters = <AdapterField>[];
    for (var name in accessorNames) {
      var getter = cls.lookUpGetter(name: name, library: library);
      if (getter != null) {
        var getterAnn =
            getHiveFieldAnn(getter.variable) ?? getHiveFieldAnn(getter);
        if (getterAnn != null) {
          var field = getter.variable;
          getters.add(
              AdapterField(getterAnn.index, field.displayName, field.type));
        }
      }

      var setter = cls.lookUpSetter(name: '$name=', library: library);
      if (setter != null) {
        var setterAnn =
            getHiveFieldAnn(setter.variable) ?? getHiveFieldAnn(setter);
        if (setterAnn != null) {
          var field = setter.variable;
          setters.add(
              AdapterField(setterAnn.index, field.displayName, field.type));
        }
      }
    }

    return [getters, setters];
  }

  void verifyFieldIndices(List<AdapterField> fields) {
    for (var field in fields) {
      check(field.index >= 0 && field.index <= 255,
          'Field numbers can only be in the range 0-255.');

      for (var otherField in fields) {
        if (otherField == field) continue;
        if (otherField.index == field.index) {
          throw HiveError(
              'Duplicate field number: ${field.index}. Fields "${field.name}" '
              'and "${otherField.name}" have the same number.');
        }
      }
    }
  }

  String getAdapterName(String typeName, ConstantReader annotation) {
    var annAdapterName = annotation.read('adapterName');
    if (annAdapterName.isNull) {
      return '${typeName}Adapter';
    } else {
      return annAdapterName.stringValue;
    }
  }

  int getTypeId(ConstantReader annotation) {
    check(
      !annotation.read('typeId').isNull,
      'You have to provide a non-null typeId.',
    );
    return annotation.read('typeId').intValue;
  }
}
