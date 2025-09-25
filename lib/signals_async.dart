import 'dart:async';

import 'package:signals/signals.dart';

/// Represents the state of an async computation that can be canceled.
///
/// This class manages the lifecycle of async operations, allowing them to be
/// canceled and providing a way to chain to new computations.
///
/// ```dart
/// // Debounced search with HTTP request cancellation
/// final searchQuery = signal('');
/// final searchSignal = ComputedAsync(searchQuery, (state, query) async {
///   // Debounce: wait 300ms before making request
///   await Future.delayed(Duration(milliseconds: 300));
///
///   // If the user continued typing in the past 300ms, this
///   // computation will have been canceled. Check if that's the case
///   if (state.isCanceled) throw Exception('Search canceled');
///
///   // Add a callback which will abort the request if the state is canceled
///   final cancelToken = CancelToken();
///   state.onCancel(() {
///     cancelToken.cancel();
///   });
///   return await client.get('https://api.example.com', cancelToken: cancelToken);
/// });
/// ```
class FutureState<O> {
  FutureState._();

  /// Returns true if this async state has been canceled.
  bool get isCanceled => __isCanceled;
  bool __isCanceled = false;
  late Function() __cancelFn = () => __isCanceled = true;

  /// Cancel the async state
  /// If a new state is provided, the future will be replaced with the new state's future
  void _cancel(FutureState<O>? newState) {
    if (!isCanceled) {
      __nextCompleter = newState?.__completer;
      __cancelFn();
    }
  }

  /// Adds a cancel callback to be executed when this async state is canceled.
  ///
  /// The callback will be called in addition to the default cancel behavior.
  /// Multiple callbacks can be added and will be executed in the order they were added.
  void onCancel(Function newOnCancel) {
    final prevOnCancel = __cancelFn;
    __cancelFn = () {
      prevOnCancel();
      newOnCancel();
    };
  }

  final __completer = Completer<O>();
  Completer<O>? __nextCompleter;

  Future<O> get _future async {
    try {
      final result = await __completer.future;
      if (__nextCompleter != null) {
        return __nextCompleter!.future;
      }
      return result;
    } catch (e) {
      if (isCanceled && __nextCompleter != null) {
        return __nextCompleter!.future;
      }
      rethrow;
    }
  }
}

class _TrackedComputed<T> extends Computed<T> with TrackedSignalMixin<T> {
  _TrackedComputed(super.fn, {super.debugLabel, super.autoDispose});
}

class ComputedFuture<O, I> extends FutureSignal<O>
    with TrackedSignalMixin<AsyncState<O>> {
  ComputedFuture._(
    this._stateSignal,
    super.fn, {
    super.debugLabel,
    super.autoDispose,
    super.lazy,
    super.initialValue,
  });
  late final Computed<FutureState<O>> _stateSignal;

  @override
  /// A future which will complete with the result of this computation.
  ///
  /// This should not be called outside of another `ComputedFuture`.
  /// Awaiting this future elsewhere will have undefined behavior.
  Future<O> get future {
    return _stateSignal.value._future;
  }

  @override
  /// The current state of this computation. Fetching this value outside of an effect/computed will result undefined behavior.
  AsyncState<O> get value => super.value;

  factory ComputedFuture(
    Future<O> Function(FutureState state) fn, {
    String? debugLabel,
    bool autoDispose = false,
    bool lazy = true,
  }) {
    // A computed signal that will provide a new state whenever the input changes
    final stateSignal = _TrackedComputed(() {
      final state = FutureState<O>._();
      void inner() async {
        try {
          state.__completer.complete(await fn(state));
        } catch (e, s) {
          state.__completer.completeError(ComputedFutureException._(e, s), s);
        }
      }

      inner();
      return state;
    }, autoDispose: autoDispose);

    // Setup the cancellation when the signal is disposed
    // NOTE: If a user is listening to a future outside of an effect/computed,
    // and this future is canceled (e.g. a cancel token is canceled),
    // this will throw an exception. This is a slight footgun that should be documented.
    stateSignal.onDispose(() {
      stateSignal.value._cancel(null);
    });

    // Return the computed future, whenever inputs change, the previous state will be canceled.
    return ComputedFuture._(
      stateSignal,
      () {
        final currentState = stateSignal.value;
        stateSignal.previousValue?._cancel(currentState);
        return currentState._future;
      },
      debugLabel: debugLabel,
      autoDispose: autoDispose,
      lazy: lazy,
    );
  }
  factory ComputedFuture.withSignal(
    ReadonlySignal<I> input,
    Future<O> Function(FutureState state, I input) fn, {
    String? debugLabel,
    bool autoDispose = false,
    bool lazy = true,
  }) {
    // A computed signal that will provide a new state whenever the input changes
    final stateSignal = _TrackedComputed(() {
      input.value; // Subscribe to the input
      final state = FutureState<O>._();
      void inner() async {
        try {
          state.__completer.complete(await fn(state, input.value));
        } catch (e, s) {
          state.__completer.completeError(ComputedFutureException._(e, s), s);
        }
      }

      inner();
      return state;
    }, autoDispose: autoDispose);

    // Setup the cancellation when the signal is disposed
    // NOTE: If a user is listening to a future outside of an effect/computed,
    // and this future is canceled (e.g. a cancel token is canceled),
    // this will throw an exception. This is a slight footgun that should be documented.
    stateSignal.onDispose(() {
      stateSignal.value._cancel(null);
    });

    // Return the computed future, whenever inputs change, the previous state will be canceled.
    return ComputedFuture._(
      stateSignal,
      () {
        final currentState = stateSignal.value;
        stateSignal.previousValue?._cancel(currentState);
        return currentState._future;
      },
      debugLabel: debugLabel,
      autoDispose: autoDispose,
      lazy: lazy,
    );
  }
}

/// An exception thrown when trying to access an async signal that is in an error state.
///
/// This is typically thrown when a [ComputedFuture] encounters an error during computation
/// or when awaiting the [future] property of a failed async signal.
///
/// ```dart
/// try {
///   final result = await myAsyncSignal.future;
/// } on ComputedFutureException catch (e) {
///   print('Error: ${e.exception}');
/// }
/// ```
final class ComputedFutureException implements Exception {
  ComputedFutureException._(this.exception, this.stackTrace);

  /// The original exception that caused the async signal to fail.
  final Object exception;

  /// The stack trace of the original exception.
  final StackTrace stackTrace;

  /// Returns a string representation of this exception.
  @override
  String toString() {
    if (exception case final ComputedFutureException exception) {
      return '''
$exception

And rethrown at:
$stackTrace''';
    }

    return '''
ComputedFutureException: Tried to use a ComputedFuture that is in error state.

A ComputedFuture threw the following exception:
$exception

The stack trace of the exception:
$stackTrace''';
  }
}
