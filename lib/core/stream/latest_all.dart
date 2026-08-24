import 'dart:async';

/// Combines the latest value of each source; emits once every source has
/// emitted, then again on any change. Each source emits on listen.
Stream<T> latestAll<T>(
  List<Stream<Object?>> sources,
  T Function(List<Object?>) project,
) {
  late final StreamController<T> controller;
  final subs = <StreamSubscription<Object?>>[];
  controller = StreamController<T>(
    onListen: () {
      final latest = List<Object?>.filled(sources.length, null);
      final ready = List<bool>.filled(sources.length, false);
      for (var i = 0; i < sources.length; i++) {
        final idx = i;
        subs.add(
          sources[idx].listen(
            (value) {
              latest[idx] = value;
              ready[idx] = true;
              if (ready.every((r) => r)) controller.add(project(latest));
            },
            onError: controller.addError,
          ),
        );
      }
    },
    onCancel: () => Future.wait(subs.map((s) => s.cancel())),
  );
  return controller.stream;
}
