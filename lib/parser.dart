import 'dart:convert';

import 'package:built_collection/src/list.dart' show ListBuilder;
import 'package:code_builder/code_builder.dart';
import 'root.dart';
import 'package:recase/recase.dart';
import 'package:tuple/tuple.dart';

class Parser {

  String parse(String jsonString, String topLevelName) {
    final decode = json.decode(jsonString);

    final List<Tuple2<String, List<Subtype>>> allClasses = [];

    //check if list or map
    if (decode is List) {}

    final List<Subtype> topLevel = _getTypedClassFields(decode);
    allClasses.add(Tuple2(topLevelName, topLevel));

    for (final s in topLevel) {
      if ((s.type == JsonType.LIST && s.listType == JsonType.MAP) ||
          s.type == JsonType.MAP) {
        final getTypedClassFields = _getTypedClassFields(s.value);
        allClasses.add(Tuple2(s.name, getTypedClassFields));
      }
    }

//    print('all: $allClasses');

//    allClasses.forEach((Tuple2<String, List<Subtype>> tuple){
//      _generateStringClass(tuple.item2, tuple.item1 + 'Dto');
//    });

    final String reduce = allClasses
        .map((tuple) => _generateStringClass(tuple.item2, tuple.item1))
        .reduce((s1, s2) => s1 + s2);

    return reduce;
  }

  String _generateStringClass(List<Subtype> topLevel, String name) {
    final topLevelClass = Class((b) => b
      ..abstract = true
      ..constructors.add(Constructor((b) => b..name = '_'))
      ..implements.add(Reference(
          'Built<${_getPascalCaseClassName(name)}, ${_getPascalCaseClassName(
              name)}Builder>'))
      ..name = _getPascalCaseClassName(name)
      ..methods = _buildMethods(topLevel)
      ..methods.add(Method((b) => b
        ..name = 'toJson'
        ..returns = const Reference('String')
        ..body = Code(
            'return json.encode(serializers.serializeWith(${_getPascalCaseClassName(
                name)}.serializer, this));')))
      ..methods.add(Method((b) => b
        ..name = 'fromJson'
        ..static = true
        ..requiredParameters.add(Parameter((b) => b
          ..name = 'jsonString'
          ..type = const Reference('String')))
        ..returns = Reference(_getPascalCaseClassName(name))
        ..body = Code(
            'return serializers.deserializeWith(${_getPascalCaseClassName(
                name)}.serializer, json.decode(jsonString));')))
      ..methods.add(Method((b) => b
        ..type = MethodType.getter
        ..name = 'serializer'
        ..static = true
        ..lambda = true
        ..returns =
            Reference('Serializer<${_getPascalCaseClassName(name)}>')
        ..body = Code('_\$${ReCase(name).camelCase}Serializer')))
      ..constructors.add(Constructor((b) => b
        ..factory = true
        ..redirect = refer(' _\$${_getPascalCaseClassName(name)}')
        ..requiredParameters.add(Parameter((b) => b
        ..defaultTo = Code('= _\$${_getPascalCaseClassName(name)}')
          ..name = '[updates(${_getPascalCaseClassName(name)}Builder b)]'))),)
          );

    final String classString = topLevelClass.accept(DartEmitter()).toString();

    final String header = """
library ${ReCase(name).snakeCase};
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part '${ReCase(name).snakeCase}.g.dart';
""";

    final String output = "$header\n$classString";

//    print(output);
    return output;
  }

  String _getPascalCaseClassName(String name) => ReCase(name).pascalCase;

  ListBuilder<Method> _buildMethods(List<Subtype> topLevel) {
    return ListBuilder(topLevel.map((Subtype s) => Method((b) => b
      ..name = ReCase(s.name).camelCase
      ..returns = _getDartType(s)
      ..annotations.add(CodeExpression(
          Code("BuiltValueField(wireName: '${s.name}')")))
      ..type = MethodType.getter)));
  }

  Reference _getDartType(Subtype subtype) {
    final JsonType type = subtype.type;
    switch (type) {
      case JsonType.INT:
        return const Reference('int?');
      case JsonType.DOUBLE:
        return const Reference('double?');
      case JsonType.BOOL:
        return const Reference('bool?');
      case JsonType.STRING:
        return const Reference('String?');
      case JsonType.MAP:
        return Reference("${ReCase(subtype.name).pascalCase}?");
      case JsonType.LIST:
        return Reference('BuiltList<${_getDartTypeFromJsonType(subtype)}>?');
      default:
        return const Reference('dynamic');
    }
  }

  String _getDartTypeFromJsonType(Subtype subtype) {
    final type = subtype.listType;
    switch (type) {
      case JsonType.INT:
        return 'int';
      case JsonType.DOUBLE:
        return 'double';
      case JsonType.STRING:
        return 'String';
      case JsonType.MAP:
        return ReCase(subtype.name).pascalCase;
      default:
        return 'dynamic';
    }
  }

  List<Subtype> _getTypedClassFields(dynamic decode) {
    final List<Subtype> topLevelClass = [];
    late final Map<String, dynamic>? toDecode;

    if (decode is List<Map<String, dynamic>>) {
      toDecode = decode[0];
    } else if (decode is Map<String, dynamic>) {
      toDecode = decode;
    }

    toDecode?.forEach((key, val) {
      topLevelClass.add(_returnType(key, val));
    });
    return topLevelClass;
  }

  Subtype _returnType(String key, dynamic val) {
    if (val is String) {
      return Subtype(key, JsonType.STRING, val);
    } else if (val is int) {
      return Subtype(key, JsonType.INT, val);
    } else if (val is num) {
      return Subtype(key, JsonType.DOUBLE, val);
    } else if (val is bool) {
      return Subtype(key, JsonType.BOOL, val);
    } else if (val is List) {
      return Subtype(key, JsonType.LIST, val,
          listType: _returnJsonType(val));
    } else if (val is Map) {
      return Subtype(key, JsonType.MAP, val);
    } else {
      throw ArgumentError('Cannot resolve JSON-encodable type for $val.');
    }
  }

  JsonType _returnJsonType(List list) {
    final item = list[0];
    print('got item $item');
    if (item is String) {
      return JsonType.STRING;
    } else if (item is int) {
      return JsonType.INT;
    } else if (item is num) {
      return JsonType.DOUBLE;
    } else if (item is bool) {
      return JsonType.BOOL;
    } else if (item is Map) {
      return JsonType.MAP;
    } else {
      throw ArgumentError('Cannot resolve JSON-encodable type for $item.');
    }
  }
}
