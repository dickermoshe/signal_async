// ignore_for_file: invalid_use_of_internal_member, depend_on_referenced_packages, implementation_imports

import 'dart:async';

import 'package:preact_signals/src/node.dart';
import 'package:signals/signals.dart';

class FutureState<O> {
  FutureState._();

  /// Returns true if this async state has been canceled.
  bool get isCanceled => __nextCompleter != null;

  final List<Function> __cancelFns = [];

  /// Cancel the async state
  /// If a new state is provided, the future will be replaced with the new state's future
  void _cancel([FutureState<O>? newState]) {
    // Never cancel a future state twice
    if (!isCanceled) {
      // If a new state is provided, use its completer
      if (newState != null) {
        __nextCompleter = newState.__completer;
      } else {
        // If we are disposing the future state without a replacement, complete with an error
        final newCompleter = Completer<O>()
          ..completeError(
            Exception("Signal was disposed before the future was completed"),
          );
        __nextCompleter = newCompleter;
      }
      // Crash the current completer so that any awaiters of `_future` will instantly
      // start await the _nextCompleter
      __completer.completeError(Exception("Future state was disposed"));

      // Execute all the cancel callbacks
      for (var cancelFn in __cancelFns) {
        cancelFn();
      }
    }
  }

  /// Adds a cancel callback to be executed when this async state is canceled.
  ///
  /// The callback will be called in addition to the default cancel behavior.
  /// Multiple callbacks can be added and will be executed in the order they were added.
  void onCancel(Function newOnCancel) {
    __cancelFns.add(newOnCancel);
  }

  final __completer = Completer<O>();
  Completer<O>? __nextCompleter;

  Future<O> get _future async {
    try {
      final result = await __completer.future;
      if (isCanceled) {
        return __nextCompleter!.future;
      }
      return result;
    } catch (e) {
      if (isCanceled) {
        return __nextCompleter!.future;
      }
      rethrow;
    }
  }
}

abstract class ComputedFuture<T> implements ReadonlySignal<AsyncState<T>> {
  Signal<AsyncState<T>> get _signal;
  void _start();
  FutureState<T>? _futureState;

  Future<T> get future {
    if (_futureState == null) {
      _start();
    }
    return _futureState!._future;
  }

  ComputedFuture._();

  static ComputedFuture<T> withSignal<T, I>(
    ReadonlySignal<I> input,
    Future<T> Function(FutureState<T> state, I input) futureBuilder, {
    bool lazy = true,
    T? initialValue,
    String? debugLabel,
    bool autoDispose = false,
  }) {
    return ComputedFutureWithDeps._(
      input,
      futureBuilder,
      lazy: lazy,
      initialValue: initialValue,
      debugLabel: debugLabel,
      autoDispose: autoDispose,
    );
  }

  factory ComputedFuture(
    Future<T> Function(FutureState<T> state) futureBuilder, {
    bool lazy = true,
    T? initialValue,
    String? debugLabel,
    bool autoDispose = false,
  }) {
    return ComputedFutureWithoutDeps._(
      futureBuilder,
      lazy: lazy,
      initialValue: initialValue,
      debugLabel: debugLabel,
      autoDispose: autoDispose,
    );
  }

  @override
  bool get autoDispose => _signal.autoDispose;

  @override
  bool get disposed => _signal.disposed;

  @override
  Node? get node => _signal.node;

  @override
  Node? get targets => _signal.targets;

  @override
  void afterCreate(AsyncState<T> val) {
    _signal.afterCreate(val);
  }

  @override
  void beforeUpdate(AsyncState<T> val) {
    _signal.beforeUpdate(val);
  }

  @override
  Symbol get brand => _signal.brand;

  @override
  AsyncState<T> call() {
    return _signal.call();
  }

  @override
  String? get debugLabel => _signal.debugLabel;

  @override
  AsyncState<T> get() {
    return _signal.get();
  }

  @override
  int get globalId => _signal.globalId;

  @override
  bool internalRefresh() {
    return _signal.internalRefresh();
  }

  @override
  AsyncState<T> get internalValue => _signal.internalValue;

  @override
  bool get isInitialized => _signal.isInitialized;

  @override
  EffectCleanup onDispose(void Function() cleanup) {
    return _signal.onDispose(cleanup);
  }

  @override
  AsyncState<T> peek() {
    return _signal.peek();
  }

  @override
  void Function() subscribe(void Function(AsyncState<T> value) fn) {
    return _signal.subscribe(fn);
  }

  @override
  void subscribeToNode(Node node) {
    _signal.subscribeToNode(node);
  }

  @override
  toJson() {
    return _signal.toJson();
  }

  @override
  void unsubscribeFromNode(Node node) {
    _signal.unsubscribeFromNode(node);
  }

  @override
  AsyncState<T> get value {
    _start();
    return _signal.value;
  }

  @override
  int get version => _signal.version;

  @override
  set autoDispose(bool autoDispose) {
    _signal.autoDispose = autoDispose;
  }

  @override
  set disposed(bool value) {
    _signal.disposed = value;
  }

  @override
  set node(Node? node) {
    _signal.node = node;
  }

  @override
  set targets(Node? targets) {
    _signal.targets = targets;
  }

  @override
  void dispose() {
    _signal.dispose();
  }
}

class ComputedFutureWithDeps<T, I> extends ComputedFuture<T> {
  final Future<T> Function(FutureState<T> state, I input) _futureBuilder;
  final ReadonlySignal<I> _input;

  @override
  late final Signal<AsyncState<T>> _signal;

  ComputedFutureWithDeps._(
    this._input,
    this._futureBuilder, {
    bool lazy = true,
    T? initialValue,
    String? debugLabel,
    bool autoDispose = false,
  }) : super._() {
    if (initialValue != null) {
      _signal = Signal(
        AsyncState.data(initialValue),
        autoDispose: autoDispose,
        debugLabel: debugLabel,
      );
    } else {
      _signal = Signal(
        AsyncState.loading(),
        autoDispose: autoDispose,
        debugLabel: debugLabel,
      );
    }
    if (!lazy) {
      _start();
    }
    _signal.onDispose(() {
      // Dispose the effect so that any changes to the input signal will be ignored
      _dispose?.call();
      // Cancel the current future state so that any awaiters of
      // the previous future state will crash
      _futureState?._cancel();
    });
  }

  Function()? _dispose;

  @override
  void _start() {
    if (_dispose != null) {
      return;
    }
    _dispose = effect(() {
      // Subscribe to the input signal
      // This will trigger three opperations below
      _input.value;

      // 1. Replace the FutureState of the previous execution
      //    with a new one.
      final currentState = _futureState;
      _futureState = FutureState<T>._();
      // 2. Cancel the previous future state.
      //    Any awaiters of the previous future state will
      //    automatically await the new future state.
      _futureState?._cancel(currentState);

      // 3. Start the requests which will update the signal and the current future state
      // as the future resolves in the background
      final state = _futureState!;
      Future(() async {
        try {
          if (state.isCanceled) return;
          _signal.value = AsyncState.loading();
          final result = await untracked(
            () => _futureBuilder(state, untracked(() => _input.value)),
          );
          if (state.isCanceled) return;
          state.__completer.complete(result);
          _signal.value = AsyncState.data(result);
        } catch (e, s) {
          if (state.isCanceled) return;
          state.__completer.completeError(e, s);
          _signal.value = AsyncState.error(e, s);
        }
      });
    });
  }
}

class ComputedFutureWithoutDeps<T> extends ComputedFuture<T> {
  final Future<T> Function(FutureState<T> state) _futureBuilder;

  @override
  late final Signal<AsyncState<T>> _signal;

  ComputedFutureWithoutDeps._(
    this._futureBuilder, {
    bool lazy = true,
    T? initialValue,
    String? debugLabel,
    bool autoDispose = false,
  }) : super._() {
    if (initialValue != null) {
      _signal = Signal(
        AsyncState.data(initialValue),
        autoDispose: autoDispose,
        debugLabel: debugLabel,
      );
    } else {
      _signal = Signal(
        AsyncState.loading(),
        autoDispose: autoDispose,
        debugLabel: debugLabel,
      );
    }
    if (!lazy) {
      _start();
    }
    _signal.onDispose(() {
      // Dispose the effect so that any changes to the input signal will be ignored
      _dispose?.call();
      // Cancel the current future state so that any awaiters of
      // the previous future state will crash
      _futureState?._cancel();
    });
  }

  Function()? _dispose;

  @override
  void _start() {
    if (_dispose != null) {
      return;
    }
    _dispose = effect(() {
      // 1. Replace the FutureState of the previous execution
      //    with a new one.
      final currentState = _futureState;
      _futureState = FutureState<T>._();
      // 2. Cancel the previous future state.
      //    Any awaiters of the previous future state will
      //    automatically await the new future state.
      _futureState?._cancel(currentState);

      // 3. Start the requests which will update the signal and the current future state
      // as the future resolves in the background
      final state = _futureState!;
      Future(() async {
        try {
          if (state.isCanceled) return;
          _signal.value = AsyncState.loading();
          final result = await untracked(() => _futureBuilder(state));
          if (state.isCanceled) return;
          state.__completer.complete(result);
          _signal.value = AsyncState.data(result);
        } catch (e, s) {
          if (state.isCanceled) return;
          state.__completer.completeError(e, s);
          _signal.value = AsyncState.error(e, s);
        }
      });
    });
  }
}
