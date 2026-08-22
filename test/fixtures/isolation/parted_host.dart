// A library whose widget is declared in a part file, and which names an SDK
// type that `material.dart` does not re-export.
//
// `package:flutter/widgets.dart` re-exports foundation as
// `show Brightness, UniqueKey`, so `DiagnosticPropertiesBuilder` is REACHABLE
// through `material.dart` and is not EXPORTED by it. A transplant that decides
// which imports to carry by walking the export graph concludes material already
// provides the name, carries no import of its own, and writes a file with an
// undefined name in it -- which `spm analyze` skips whole. Every
// `debugFillProperties` override in real code is an instance of this.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

part 'parted_widget.dart';
