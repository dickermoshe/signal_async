import 'dart:async';

import 'package:signals/signals.dart';

abstract class ComputedStream<Output>
    implements ReadonlySignal<AsyncState<Output>> {
  Future<Output> get future;

  factory ComputedStream(
    Stream<Output> Function() streamBuilder, {
    Output? initialValue,
    bool lazy = true,
    bool autoDispose = false,
    String? debugLabel,
  }) {
    final result = _ComputedStreamImpl(
      streamBuilder,
      initialValue: initialValue,
      autoDispose: autoDispose,
      debugLabel: debugLabel,
    );
    if (!lazy) {
      result.start();
    }
    return result;
  }
}

class _ComputedStreamImpl<Output> extends Signal<AsyncState<Output>>
    implements ComputedStream<Output> {
  final Stream<Output> Function() streamBuilder;

  StreamSubscription<Output>? subscription;
  Completer<Output> completer = Completer<Output>();

  _ComputedStreamImpl(
    this.streamBuilder, {
    required Output? initialValue,
    required super.autoDispose,
    required super.debugLabel,
  }) : super(
         initialValue != null
             ? AsyncState.data(initialValue)
             : AsyncState.loading(),
       ) {
    if (initialValue != null) {
      completer.complete(initialValue);
    }
  }
  bool started = false;

  void start({bool force = false}) {
    if (started && !force) {
      return;
    }
    started = true;

    subscription = streamBuilder().listen(
      (event) {
        if (completer.isCompleted) {
          completer = Completer<Output>();
        }
        batch(() {
          completer.complete(event);

          value = AsyncState.data(event);
        });
      },
      onError: (error, stackTrace) {
        if (completer.isCompleted) {
          completer = Completer<Output>();
        }
        batch(() {
          completer.completeError(error, stackTrace);
          value = AsyncState.error(error, stackTrace);
        });
      },
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Signal was disposed before the future was completed'),
      );
    }
    super.dispose();
  }

  @override
  Future<Output> get future {
    value;
    return completer.future;
  }

  @override
  AsyncState<Output> get value {
    start();
    return super.value;
  }
}
