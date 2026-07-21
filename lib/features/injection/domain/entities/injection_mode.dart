/// The two injection modes supported by the tool.
enum InjectionMode {
  /// Replaces `extends State<T>` with `extends SpmState<T>` and adds the
  /// `instanceId` getter for each target class.
  inject,

  /// Reverts previously injected `SpmState` changes back to `State`.
  remove;

  /// Parses a CLI string (e.g. `'inject'`) into an [InjectionMode].
  static InjectionMode fromCli(String value) => InjectionMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'mode',
      'Must be one of: ${InjectionMode.values.map((m) => m.name).join(', ')}',
    ),
  );
}
