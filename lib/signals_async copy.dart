library;

import 'dart:async';

import 'package:signals/signals.dart';

typedef ComputedFutureBuilder<Output, Input> =
    Future<Output> Function(FutureState<Output> state, Input input);

/// A reactive asynchronous signal that computes a [Future] based on input signals
/// or manually via [restart].
///
/// `ComputedFuture` extends the signals library to handle asynchronous operations
/// reactively. It tracks dependencies (via an input signal) and automatically
/// restarts computations when inputs change, while supporting cancellation,
/// lazy evaluation, and disposal.
///
/// Use the default constructor for reactive scenarios (e.g., API calls driven
/// by user input). Use [ComputedFuture.nonReactive] for one-off async tasks
/// (e.g., initial data fetch) that can be manually restarted.
///
/// ## Key Features:
/// - **Reactivity**: Depends on a [ReadonlySignal<Input>] to trigger recomputations.
/// - **Cancellation**: Supports robust cancellation during restarts or disposal,
///   preserving awaiters on [future].
/// - **Lazy Evaluation**: Defaults to lazy (starts on first access); set `lazy: false` for eager.
/// - **Initial Value**: Optional `initialValue` to avoid loading flickers.
/// - **Auto-Disposal**: If `autoDispose: true`, cancels on effect disposal.
/// - **State Management**: Exposes [AsyncState<Output>] via `value`, and raw [Future<Output>] via `future`.
///
abstract class ComputedFuture<Output, Input>
    implements ReadonlySignal<AsyncState<Output>> {
  Future<Output> get future;

  /// Manually restarts the computation.
  ///
  /// Cancels any ongoing future and schedules a new one using the current input
  /// value (or just the builder in non-reactive mode). Useful for refresh buttons
  /// or polling.
  ///
  /// This will have no effect if the computation is lazy and has not yet started.
  ///
  /// ## Example
  /// ```dart
  /// fetchData.restart();  // Refresh data manually
  /// ```
  void restart();

  /// Creates a reactive [ComputedFuture] that recomputes when [input] changes.
  ///
  /// The [futureBuilder] receives the current [FutureState] (for cancellation
  /// checks) and the input value.
  ///
  /// - [input]: The signal to watch for changes.
  /// - [futureBuilder]: Builds the [Future<Output>] based on state and input.
  /// - [initialValue]: Optional initial data to show before first computation.
  /// - [lazy]: If `true` (default), starts on first access; if `false`, eager.
  /// - [autoDispose]: If `true`, cancels on effect disposal.
  /// - [debugLabel]: Optional label for debugging (e.g., in signal traces).
  ///
  /// ## Example: Basic Reactive Computation
  /// ```dart
  /// final input = signal(2);
  /// final result = ComputedFuture(input, (state, value) async {
  ///   // Use 'state' for onCancel() or check isCanceled
  ///   await Future.delayed(Duration(seconds: 1));
  ///   if (state.isCanceled) return 0;  // Handle cancel gracefully
  ///   return value * 2;
  /// });
  ///
  /// // Listen to state changes
  /// effect(() {
  ///   final state = result.value;
  ///   if (state is AsyncData<int>) {
  ///     print('Result: ${state.value}');  // Prints 4 initially
  ///   }
  /// });
  ///
  /// input.value = 3;  // Triggers recompute, prints 6
  /// ```
  ///
  /// ## Example: Multiple Inputs with Dart Records
  /// ```dart
  /// final userId = signal(1);
  /// final category = signal('electronics');
  ///
  /// // Use a computed signal to combine multiple inputs into a record
  /// final searchParams = computed(() => (userId: userId.value, category: category.value));
  ///
  /// final searchResults = ComputedFuture(searchParams, (state, params) async {
  ///   // Access record fields: params.userId, params.category
  ///   final response = await http.get(Uri.parse(
  ///     'https://api.example.com/search?user=${params.userId}&category=${params.category}'
  ///   ));
  ///   return jsonDecode(response.body);
  /// });
  ///
  /// // Changing either input triggers a new search
  /// userId.value = 2;      // Triggers recompute
  /// category.value = 'books';  // Triggers recompute
  /// ```
  ///
  /// ## Example: Chaining ComputedFutures
  /// ```dart
  /// final userId = signal(1);
  ///
  /// // First future: fetch user profile
  /// final userProfile = ComputedFuture(userId, (state, id) async {
  ///   final response = await http.get(Uri.parse('https://api.example.com/users/$id'));
  ///   return jsonDecode(response.body);
  /// });
  ///
  /// // Second future depends on the first: fetch user's posts
  /// // IMPORTANT: Pass the ComputedFuture itself as the input
  /// final userPosts = ComputedFuture(userProfile, (state, _) async {
  ///   // Await the previous future to get the user profile
  ///   final profile = await userProfile.future;
  ///   final response = await http.get(Uri.parse(
  ///     'https://api.example.com/posts?author=${profile['username']}'
  ///   ));
  ///   return jsonDecode(response.body);
  /// });
  ///
  /// // When userId changes, both futures will recompute in sequence
  /// userId.value = 2;  // userProfile recomputes, then userPosts recomputes
  /// ```
  factory ComputedFuture(
    ReadonlySignal<Input> input,
    ComputedFutureBuilder<Output, Input> futureBuilder, {
    Output? initialValue,
    bool lazy = true,
    bool autoDispose = false,
    String? debugLabel,
  }) {
    final result = _ComputedFutureImpl(
      input,
      futureBuilder,
      autoDispose: autoDispose,
      debugLabel: debugLabel,
      initialValue: initialValue,
    );

    if (!lazy) {
      result.start();
    }
    return result;
  }

  /// Creates a non-reactive [ComputedFuture] that runs independently of signals.
  ///
  /// The [futureBuilder] receives only the [FutureState] (no input dependency).
  /// Computations run on creation (if eager) or first access, and can be manually
  /// restarted. Ideal for one-off async tasks like initial loads or user-triggered
  /// actions.
  ///
  /// Internally uses a dummy `void` input for compatibility.
  ///
  /// - [futureBuilder]: Builds the [Future<Output>] based on state.
  /// - [initialValue]: Optional initial data to show before first computation.
  /// - [lazy]: If `true` (default), starts on first access; if `false`, eager.
  /// - [autoDispose]: If `true`, cancels on effect disposal.
  /// - [debugLabel]: Optional label for debugging.
  ///
  /// ## Example: Non-Reactive with Manual Restart
  /// ```dart
  /// final fetchData = ComputedFuture.nonReactive((state) async {
  ///   // Non-reactive: ignores external signals
  ///   final response = await http.get(Uri.parse('https://api.example.com/data'));
  ///   state.onCancel(() => controller?.dispose());  // Cleanup on cancel/restart
  ///   return jsonDecode(response.body);
  /// });
  ///
  /// effect(() => print(fetchData.value));  // Triggers initial fetch
  ///
  /// fetchData.restart();  // Manual refresh, cancels previous if running
  /// ```
  static ComputedFuture<Output, void> nonReactive<Output>(
    Future<Output> Function(FutureState<Output> state) futureBuilder, {
    Output? initialValue,
    bool lazy = true,
    bool autoDispose = false,
    String? debugLabel,
  }) {
    final input = signal(null);
    Future<Output> wrappedFutureBuilder(
      FutureState<Output> state,
      void input,
    ) => futureBuilder(state);
    final result = _ComputedFutureImpl<Output, void>(
      input,
      wrappedFutureBuilder,
      autoDispose: autoDispose,
      debugLabel: debugLabel,
      initialValue: initialValue,
    );
    if (!lazy) {
      result.start();
    }

    return result;
  }
}

/// A reactive asynchronous signal that wraps a [Stream] and exposes its latest value
/// as an [AsyncState].
///
/// `ComputedStream` extends the signals library to handle stream-based operations
/// reactively. It automatically subscribes to the stream when accessed and updates
/// its value as new stream events arrive.
///
/// ## Key Features:
/// - **Stream Integration**: Wraps any Stream<T> into a reactive signal
/// - **Latest Value Access**: Always provides the most recent stream value
/// - **Error Handling**: Properly handles stream errors as AsyncError states
/// - **Lazy Subscription**: Defaults to lazy (subscribes on first access)
/// - **Auto-Disposal**: Cancels stream subscription when disposed
/// - **Future Integration**: Provides future access to stream values
///
/// ## Example: Basic Stream Usage
/// ```dart
/// final controller = StreamController<int>();
/// final streamSignal = ComputedStream(() => controller.stream);
///
/// effect(() {
///   final state = streamSignal.value;
///   if (state.hasValue) {
///     print('Stream value: ${state.value}');
///   }
/// });
///
/// controller.add(42); // Prints: Stream value: 42
/// controller.close();
/// ```
///
/// ## Example: WebSocket Integration
/// ```dart
/// final websocketStream = ComputedStream(() {
///   return WebSocket.connect('ws://localhost:8080')
///       .asStream()
///       .asyncExpand((ws) => ws.cast<String>());
/// });
///
/// effect(() {
///   final state = websocketStream.value;
///   if (state.hasValue) {
///     print('Received: ${state.value}');
///   } else if (state.hasError) {
///     print('WebSocket error: ${state.error}');
///   }
/// });
/// ```
///
/// ## Example: Stream with Initial Value
/// ```dart
/// final dataStream = ComputedStream(
///   () => Stream.periodic(Duration(seconds: 1), (i) => i),
///   initialValue: -1, // Show this before first stream value
/// );
/// ```
abstract class ComputedStream<Output>
    implements ReadonlySignal<AsyncState<Output>> {
  /// Returns a future that completes with the next stream value.
  ///
  /// If the stream has already emitted a value, returns that value immediately.
  /// If an initial value was provided, returns that value immediately.
  Future<Output> get future;

  /// Creates a [ComputedStream] that wraps the provided stream.
  ///
  /// The [streamBuilder] function is called to create the stream when the
  /// signal is first accessed (lazy) or immediately (eager).
  ///
  /// - [streamBuilder]: Function that returns the stream to wrap
  /// - [initialValue]: Optional initial value to show before first stream event
  /// - [lazy]: If `true` (default), subscribes on first access; if `false`, subscribes immediately
  /// - [autoDispose]: If `true`, cancels subscription when effect disposal occurs
  /// - [debugLabel]: Optional label for debugging purposes
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

  /// The subscription to the stream
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
    Effect(() {});
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
    // Subscribing to the current signal
    // This will also call start() under the hood
    value;
    return completer.future;
  }

  @override
  AsyncState<Output> get value {
    start();
    return super.value;
  }
}

/// Internal implementation of [ComputedFuture].
///
/// Manages the signal state, effect tracking, and lifecycle. Not intended for
/// direct use—use the factory constructors.
class _ComputedFutureImpl<Output, Input> extends Signal<AsyncState<Output>>
    implements ComputedFuture<Output, Input> {
  _ComputedFutureImpl(
    this.input,
    this.futureBuilder, {
    required super.autoDispose,
    required super.debugLabel,
    required Output? initialValue,
  }) : usingInitialValue = initialValue != null,
       super(
         initialValue != null
             ? AsyncState.data(initialValue)
             : AsyncState.loading(),
       );

  /// The function to build the future
  final ComputedFutureBuilder<Output, Input> futureBuilder;

  /// The input signal which will be used to trigger new requests
  final ReadonlySignal<Input> input;

  /// Whether the signal is still using the initial value
  bool usingInitialValue;

  // A function to dispose the effect which tracks the input signal
  // and triggers new requests
  Function()? disposeEffect;

  /// The state of the current running future
  /// As futures are canceled and restarted, this object helps with
  /// managing that transition.
  FutureState<Output>? futureState;

  /// This will be set to true once we've started making requests.
  ///
  /// That will only happen once this signal is depended on, or if lazy has been set to false.
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
    return futureState!._future;
  }

  @override
  void dispose() {
    disposeEffect?.call();
    futureState?._cancel();
    super.dispose();
  }

  /// Starts the reactive effect if not already running.
  ///
  /// Called implicitly on `value` or `future` access in lazy mode.
  /// Sets up the effect to watch [input] and [counter] for changes,
  /// handling restarts and cancellations.
  void start() {
    if (started) {
      return;
    }

    started = true;
    disposeEffect = effect(() {
      // Subscribe to the input signal and counter signals
      // This will trigger three operations below whenever either signal changes
      (counter.value, input.value);

      // 1. Replace the FutureState of the previous execution
      //    with a new one.
      final previousState = futureState;
      futureState = FutureState<Output>._(this);

      // 2. Cancel the previous future state.
      //    Any awaiters of the previous future state will
      //    automatically await the new future state.
      previousState?._cancel(futureState);

      // 3. Start the requests which will update the signal and the current future state
      // as the future resolves in the background
      final state = futureState!;
      Future.delayed(Duration.zero)
          .then((_) {
            // If the user created the signal with an initial value,
            // we should show that value until the future resolves
            if (!usingInitialValue) {
              if (untracked(() => value) is! AsyncLoading) {
                value = AsyncState.loading();
              }
            }
          })
          .then((_) {
            Future<Output> inner() async {
              if (state.isCanceled) {
                throw StateError(
                  'Signal was disposed before the future was completed',
                );
              }
              final value = untracked(() => input.value);
              final future = untracked(() => futureBuilder(state, value));
              return future;
            }

            return inner();
          })
          .then(state._complete)
          .catchError(state._completeError)
          .whenComplete(() {
            usingInitialValue = false;
          })
          .ignore();
    });
  }
}

/// Manages the state of an asynchronous operation with cancellation support.
///
/// Wraps a [Signal<AsyncState<O>>] and provides methods to complete, cancel,
/// and track the lifecycle of async operations.
///
/// Passed to the [futureBuilder] in [ComputedFuture] to enable cancellation
/// awareness (e.g., check [isCanceled] or register [onCancel] callbacks).
/// Handles switching awaiters seamlessly during cancels/restarts.
class FutureState<O> {
  final Signal<AsyncState<O>> __signal;
  FutureState._(this.__signal);

  bool _isCanceled = false;

  /// Returns true if the running future has been canceled.
  ///
  /// Check this in the [futureBuilder] to abort work early and avoid
  /// unnecessary computation after cancel (e.g., on signal change or dispose).
  bool get isCanceled => _isCanceled;

  final List<Function> __cancelFns = [];

  /// Completes the async operation with a successful value.
  void _complete(O value) {
    if (__completer.isCompleted || isCanceled) {
      return;
    }
    // The order of operations is important here
    // Setting a signal will trigger the effects synchronously
    // Completing the completer will only have an effect until the next tick
    // We don't want any race conditions between the completer and the signal
    // so we set the completer first and then the signal
    batch(() {
      __completer.complete(value);
      __signal.value = AsyncState.data(value);
    });
  }

  /// Completes the async operation with an error.
  void _completeError(Object error, StackTrace stackTrace) {
    if (__completer.isCompleted || isCanceled) {
      return;
    }
    // The order of operations is important here
    // See _complete for more details
    batch(() {
      __completer.completeError(error, stackTrace);
      __signal.value = AsyncState.error(error, stackTrace);
    });
  }

  /// Cancel the async state.
  ///
  /// Replaces the current [Completer] with a new one (from [newState] if provided,
  /// or a failed one on dispose). Executes all [onCancel] callbacks in order.
  /// Awaiters on [_future] automatically switch to the next completer.
  ///
  /// If no [newState], completes with a disposal error.
  ///
  /// Internal: Called on signal changes, restarts, or dispose.
  void _cancel([FutureState<O>? newState]) {
    // Never cancel a future state twice
    if (!isCanceled) {
      _isCanceled = true;
      __nextState = newState;

      // Execute all the cancel callbacks
      for (var cancelFn in __cancelFns) {
        try {
          cancelFn();
        } catch (e) {
          // ignore: empty_catches
        }
      }
      // Crash the current completer so that any awaiters of `_future` will instantly
      // start await the __nextState
      if (!__completer.isCompleted) {
        __completer.completeError(
          StateError("Signal was disposed before the future was completed"),
        );
      }
    }
  }

  /// Adds a cancel callback to be executed when this async state is canceled.
  ///
  /// Callbacks run in addition to default cancellation, in the order added.
  /// Useful for cleanup (e.g., closing streams, aborting HTTP requests).
  ///
  /// Errors in callbacks are caught and ignored to ensure all run.
  ///
  /// ## Multiple Callbacks
  /// ```dart
  /// state.onCancel(() => stream1.cancel());  // First
  /// state.onCancel(() => timer.cancel());    // Executes after first
  /// ```
  ///
  /// Call this early in the [futureBuilder]—before async work starts.
  void onCancel(Function newOnCancel) {
    __cancelFns.add(newOnCancel);
  }

  final __completer = Completer<O>();
  FutureState<O>? __nextState;

  /// Returns the future that will complete when the async operation finishes.
  ///
  /// Handles cancellation by switching to the next completer if canceled.
  /// Awaiters are preserved across switches (e.g., during restarts).
  ///
  /// Internal: Accessed via [ComputedFuture.future].
  Future<O> get _future async {
    try {
      final result = await __completer.future;
      if (isCanceled) {
        return __nextState!._future;
      }
      return result;
    } catch (e) {
      if (isCanceled) {
        return __nextState!._future;
      }
      rethrow;
    }
  }
}
