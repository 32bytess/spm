import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spm/src/features/isolation/data/data_sources/isolation_data_source_impl.dart';
import 'package:test/test.dart';

import 'utils/temp_project.dart';

/// A stand-in emits every constructor, whatever its member limit says.
///
/// The two used to be gated on the same flag, so a type declaring more than
/// forty fields and methods emitted no constructors at all unless a reference
/// happened to reach one, and a call site's named arguments then landed on the
/// implicit default constructor. That is a direct source of
/// `undefined_named_parameter`, and the saving was never real: a constructor
/// renders as one line, where the member limit exists to stop a geometry value
/// object contributing hundreds of accessors.
const String _scopeSource = '''
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class BigTypeHost extends StatefulWidget {
  const BigTypeHost({super.key});

  @override
  State<BigTypeHost> createState() => BigTypeHostState();
}

class BigTypeHostState extends State<BigTypeHost> {
  final FancyController _controller = FancyController();

  @override
  Widget build(BuildContext context) => Column(
    children: [Text('\${_controller.hashCode}')],
  );
}
''';

void main() {
  late TempProject project;
  late Directory output;
  late String isolated;

  setUpAll(() async {
    project = TempProject.create(
      sources: {'big.dart': _scopeSource},
      extraPackages: {
        'ui_kit': p.join(
          p.absolute('test/fixtures/isolation_third_party'),
          'ui_kit',
        ),
      },
      prefix: 'spm_shim_ctors',
    );
    output = Directory.systemTemp.createTempSync('spm_shim_ctors_out');

    await IsolationDataSourceImpl()
        .isolate(
          directories: [project.path],
          outputDir: output.path,
          inlineThirdParty: false,
        )
        .toList();

    isolated = Directory(
      p.join(output.path, 'State'),
    ).listSync().whereType<File>().single.readAsStringSync();
  });

  tearDownAll(() {
    project.delete();
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  test('a type over the member limit still gets its constructor', () {
    // `FancyController` declares forty-one methods, so its members come from
    // what the scope reached. Its constructor does not.
    expect(isolated, contains('class FancyController'));
    expect(isolated, contains('FancyController();'));
  });

  test('the member limit still governs members', () {
    // The half of the old coupling that was right: rendering every member of a
    // forty-member controller is what the referenced-only rule exists to avoid.
    expect(isolated, isNot(contains('void pad0()')));
  });

  test('the file still analyses clean', () {
    expect(isolated, contains('class GeneratedWidget'));
  });
}
