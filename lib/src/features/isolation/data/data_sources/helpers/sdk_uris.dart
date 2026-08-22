/// Whether [uri] names a library the isolated file is allowed to import.
///
/// The transplant imports the Dart SDK and the Flutter SDK and nothing else.
/// Every other library is either carried into the output as source or stood in
/// for, so that the output analyses inside a package that depends on `flutter`
/// alone. Which of the two a declaration gets is decided in
/// `dependency_extractor_visitor.dart`; this only decides what may be imported
/// rather than carried. The trailing slash is what makes
/// this a Flutter SDK test rather than a "starts with the word flutter" test.
/// Without it `package:flutter_bloc`, `package:flutter_riverpod`,
/// `package:flutter_scale_kit` and every other `flutter_`-prefixed pub package
/// read as SDK libraries, get imported instead of shimmed, and leave the
/// isolated file depending on packages that are not there.
bool isSdkLibrary(String uri) =>
    uri.startsWith('dart:') || uri.startsWith('package:flutter/');
