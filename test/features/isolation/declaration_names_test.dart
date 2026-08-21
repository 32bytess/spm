import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:spm/src/features/isolation/data/data_sources/helpers/declaration_names.dart';
import 'package:test/test.dart';

Set<String> namesOf(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  return {for (final decl in unit.declarations) ...declaredNames(decl)};
}

void main() {
  group('declaredNames', () {
    test('names a class', () {
      expect(namesOf('class Foo {}'), {'Foo'});
    });

    test('names an extension type', () {
      expect(namesOf('extension type Meters(int value) {}'), {'Meters'});
    });

    test('names a const extension type with type parameters', () {
      expect(namesOf('extension type const Box<T>(T value) {}'), {'Box'});
    });

    test('names every variable in a top-level list', () {
      expect(namesOf('const a = 1, b = 2;'), {'a', 'b'});
    });
  });
}
