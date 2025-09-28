import 'dart:async';
import 'package:signals/signals.dart';

class CanceledFutureException implements Exception {
  final message = 'This future was canceled before it completed';

  CanceledFutureException();
}

class AsyncStateContainer<T> {
  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;

  late AsyncState<T> _state;
  AsyncState<T> get state => _nextState?.state ?? _state;
  Completer<T>? _completer;

  Future<T>? _future;
  Future<T> get future {
    if (_future != null) {
      return _future!;
    }

    // Start the future in the background
    run();

    // Define a future which will fallback to
    // the future of the next container if this one is canceled
    Future<T> inner() async {
      try {
        final result = await _completer!.future;
        if (isCanceled) {
          if (_nextState != null) {
            return _nextState!.future;
          }
          throw CanceledFutureException();
        }
        return result;
      } catch (e) {
        if (isCanceled) {
          if (_nextState != null) {
            return _nextState!.future;
          }
          throw CanceledFutureException();
        }
        rethrow;
      }
    }

    _future = inner();
    return _future!;
  }

  final List<Function> _cancelFns = [];

  /// Add a cancel function to the container
  /// The function will be called when the container is canceled
  void onCancel(Function newOnCancel) {
    _cancelFns.add(newOnCancel);
  }

  /// Cancel the container
  /// If a next state is provided, the future of this container will be chained
  /// to the future of the next container
  void cancel([AsyncStateContainer<T>? nextState]) {
    _isCanceled = true;
    _nextState = nextState;
    for (var cancelFn in _cancelFns) {
      try {
        cancelFn();
      } catch (e) {
        // ignore: empty_catches
      }
    }
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(CanceledFutureException());
    }
  }

  // The container which has replaced this one
  // This is used to chain the future of this container
  // to the future of the next container
  AsyncStateContainer<T>? _nextState;

  /// The function which will be used to build the future
  final Future<T> Function(AsyncStateContainer<T> state) _futureBuilder;

  /// The constructor for the AsyncStateContainer
  /// The initial value is used to set the initial state of the container
  /// If no initial value is provided, the container will start in a loading state
  AsyncStateContainer(
    this._futureBuilder, {
    T? initialValue,
    bool lazy = true,
  }) {
    if (initialValue != null) {
      _state = AsyncState.data(initialValue);
    } else {
      _state = AsyncState.loading();
    }
    if (!lazy) {
      run();
    }
  }

  void run() async {
    if (_completer != null) {
      return;
    }
    _completer = Completer<T>();

    // The completers future should not
    // report background errors to the zone
    _completer!.future.ignore();

    // This await is used to ensure that
    // no synchronous parts of the future run until the next tick
    await Future.delayed(Duration.zero);
    try {
      final result = await _futureBuilder(this);
      _state = AsyncState.data(result);
      _completer!.complete(result);
    } catch (e) {
      _state = AsyncState.error(e);
      // If this future was canceled, the completer will already be completed
      // so we don't need to complete it again
      if (!_completer!.isCompleted) {
        _completer!.completeError(e);
      }
    }
  }
}
