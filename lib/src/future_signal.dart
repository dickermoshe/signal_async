import 'dart:async';

import 'package:signals/signals.dart';
import 'package:signals_async/src/async_state_container.dart';

typedef ComputedFutureBuilder<Output> =
    Future<Output> Function(AsyncStateContainer<Output> state);

abstract class ComputedFuture<Output>
    implements ReadonlySignal<AsyncState<Output>> {
  Future<Output> get future;

  void restart();

  factory ComputedFuture(
    List<ReadonlySignal> dependencies,
    ComputedFutureBuilder<Output> futureBuilder, {
    Output? initialValue,
    bool lazy = true,
    bool autoDispose = false,
    String? debugLabel,
  }) {
    AsyncStateContainer<Output> containerBuilder() =>
        AsyncStateContainer<Output>(
          futureBuilder,
          initialValue: initialValue,
          lazy: lazy,
        );
    final containerSignal = Signal<AsyncStateContainer<Output>>(
      containerBuilder(),
    );

    return _ComputedFutureImpl(
      dependencies,
      containerBuilder,
      containerSignal,
      autoDispose: autoDispose,
      debugLabel: debugLabel,
    );
  }
  factory ComputedFuture.nonReactive(
    ComputedFutureBuilder<Output> futureBuilder, {
    Output? initialValue,
    bool lazy = true,
    bool autoDispose = false,
    String? debugLabel,
  }) {
    AsyncStateContainer<Output> containerBuilder() =>
        AsyncStateContainer<Output>(
          futureBuilder,
          initialValue: initialValue,
          lazy: lazy,
        );
    final containerSignal = Signal<AsyncStateContainer<Output>>(
      containerBuilder(),
    );

    return _ComputedFutureImpl(
      [],
      containerBuilder,
      containerSignal,
      autoDispose: autoDispose,
      debugLabel: debugLabel,
    );
  }
}

class _ComputedFutureImpl<Output> extends Computed<AsyncState<Output>>
    implements ComputedFuture<Output> {
  _ComputedFutureImpl(
    this.dependencies,
    this.containerBuilder,
    this.containerSignal, {
    required super.autoDispose,
    required super.debugLabel,
  }) : super(() => containerSignal.value.value);

  final AsyncStateContainer<Output> Function() containerBuilder;
  final Signal<AsyncStateContainer<Output>> containerSignal;

  final List<ReadonlySignal> dependencies;

  Function()? disposeEffect;

  bool started = false;

  final counter = signal(0);

  @override
  void restart() {
    counter.value++;
  }

  @override
  AsyncState<Output> get value {
    start();
    return super.value;
  }

  @override
  Future<Output> get future {
    start();
    return containerSignal.value.future;
  }

  @override
  void dispose() {
    disposeEffect?.call();
    containerSignal.value.cancel();
    super.dispose();
  }

  void start() {
    if (started) {
      return;
    }

    started = true;
    disposeEffect = effect(() {
      counter.value;
      for (var dependency in dependencies) {
        dependency.value;
      }
      final nextContainer = containerBuilder()..run();
      untracked(() {
        containerSignal.value.cancel(nextContainer);
      });

      containerSignal.value = nextContainer;
    });
  }
}
