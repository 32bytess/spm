/// The one-feature rule: an edit is likely slower when it adds non-const
/// widgets to the rebuild scope.
///
/// On the thesis's real-history pairs this rule agreed with the measured
/// direction more often than the forest did; on the controlled variants the
/// forest was better. `spm screen` therefore prints both.
class CountRule {
  CountRule._();

  static const feature = 'treeNonConstWidgetCount';

  /// True when the after-version builds more non-const widgets. A zero delta
  /// predicts "not slower".
  static bool slower(Map<String, num> delta) => (delta[feature] ?? 0) > 0;
}
