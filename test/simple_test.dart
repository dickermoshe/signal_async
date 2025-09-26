import 'dart:async';

import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';
import 'package:test/test.dart';

// A test which won't fail if it throws an error in the background.
void mytest(String name, FutureOr<void> Function() testFn) {
  test(name, () async {
    await runZonedGuarded(testFn, (error, stack) {});
  });
}

void main() async {
  group("ComputedFuture.nonReactive() constructor", () {
    group("basic functionality", () {
      mytest('creates and executes future computation', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 42;
        });

        expect(computed.peek(), AsyncState.loading());
        final events = [];
        effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(events, [AsyncState.loading(), AsyncState.data(42)]);
      });

      mytest('computation receives FutureState parameter', () async {
        FutureState? receivedState;
        final computed = ComputedFuture.nonReactive((state) async {
          receivedState = state;
          return 'test';
        });

        effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 10));
        expect(receivedState, isNotNull);
        expect(receivedState!.isCanceled, false);
      });

      mytest('supports debugLabel parameter', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          return 'labeled';
        }, debugLabel: 'test-label');

        expect(computed.debugLabel, 'test-label');
      });
    });

    group("lazy behavior", () {
      mytest(
        'lazy=true (default) - computation starts when accessed',
        () async {
          bool computationStarted = false;
          final computed = ComputedFuture.nonReactive((state) async {
            computationStarted = true;
            await Future.delayed(Duration(milliseconds: 10));
            return 'result';
          });

          // Should not start computation immediately
          await Future.delayed(Duration(milliseconds: 20));
          expect(computationStarted, false);

          // Should start when accessed
          effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 20));
          expect(computationStarted, true);
        },
      );

      mytest('lazy=false - computation starts immediately', () async {
        bool computationStarted = false;
        final computed = ComputedFuture.nonReactive((state) async {
          computationStarted = true;
          await Future.delayed(Duration(milliseconds: 10));
          return 'result';
        }, lazy: false);

        // Should start computation immediately
        await Future.delayed(Duration(milliseconds: 20));
        expect(computationStarted, true);
        expect(computed.peek(), AsyncState.data('result'));
      });
    });

    group("autoDispose behavior", () {
      mytest(
        'autoDispose=true cancels computation when effect disposed',
        () async {
          final events = [];
          bool computationCompleted = false;

          final computed = ComputedFuture.nonReactive((state) async {
            events.add('started');
            await Future.delayed(Duration(milliseconds: 30));

            if (state.isCanceled) {
              events.add('canceled');
              throw Exception('Computation canceled');
            }

            events.add('completed');
            computationCompleted = true;
            return 'result';
          }, autoDispose: true);

          final dispose = effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 10));
          dispose(); // Dispose effect before computation completes

          await Future.delayed(Duration(milliseconds: 50));
          expect(events, ['started', 'canceled']);
          expect(computationCompleted, false);
        },
      );

      mytest(
        'autoDispose=false allows computation to complete after effect disposed',
        () async {
          final events = [];

          final computed = ComputedFuture.nonReactive((state) async {
            events.add('started');
            await Future.delayed(Duration(milliseconds: 30));

            if (state.isCanceled) {
              events.add('canceled');
              return 'canceled';
            }

            events.add('completed');
            return 'result';
          }, autoDispose: false);

          final dispose = effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 10));
          dispose(); // Dispose effect before computation completes

          await Future.delayed(Duration(milliseconds: 50));
          expect(events, ['started', 'completed']);
        },
      );
    });

    group("error handling", () {
      mytest('handles synchronous errors', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          throw Exception('Sync error');
        });

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);
        expect(events[1].error, isA<Exception>());
      });

      mytest('handles asynchronous errors', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Async error');
        });

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);
        expect(events[1].error, isA<Exception>());
      });
    });

    group("cancellation behavior", () {
      mytest(
        'state.isCanceled becomes true when computation is canceled',
        () async {
          bool wasCanceled = false;
          final computed = ComputedFuture.nonReactive((state) async {
            await Future.delayed(Duration(milliseconds: 30));
            wasCanceled = state.isCanceled;
            return 'result';
          }, autoDispose: true);

          final dispose = effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 10));
          dispose(); // Cancel the computation

          await Future.delayed(Duration(milliseconds: 50));
          expect(wasCanceled, true);
        },
      );

      mytest('onCancel callback is executed when canceled', () async {
        final cancelEvents = [];
        final computed = ComputedFuture.nonReactive((state) async {
          state.onCancel(() {
            cancelEvents.add('cleanup executed');
          });

          await Future.delayed(Duration(milliseconds: 30));
          return 'result';
        }, autoDispose: true);

        final dispose = effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 10));
        dispose();

        await Future.delayed(Duration(milliseconds: 50));
        expect(cancelEvents, ['cleanup executed']);
      });

      mytest('multiple onCancel callbacks are executed in order', () async {
        final cancelEvents = [];
        final computed = ComputedFuture.nonReactive((state) async {
          state.onCancel(() => cancelEvents.add('first'));
          state.onCancel(() => cancelEvents.add('second'));
          state.onCancel(() => cancelEvents.add('third'));

          await Future.delayed(Duration(milliseconds: 30));
          return 'result';
        }, autoDispose: true);

        final dispose = effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 10));
        dispose();

        await Future.delayed(Duration(milliseconds: 50));
        expect(cancelEvents, ['first', 'second', 'third']);
      });
    });

    group("future property", () {
      mytest('future property returns computation result', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'future result';
        });

        effect(() {
          computed.value; // Start computation
        });

        final result = await computed.future;
        expect(result, 'future result');
      });

      mytest('future property throws on error', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Future error');
        });

        effect(() {
          computed.value; // Start computation
        });

        try {
          await computed.future;
          // ignore: dead_code
          fail('Expected exception to be thrown');
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('Future error'));
        }
      });

      mytest('future property handles cancellation', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          await Future.delayed(Duration(milliseconds: 30));
          if (state.isCanceled) {
            throw Exception('Canceled');
          }
          return 'result';
        }, autoDispose: true);

        final dispose = effect(() {
          computed.value;
        });

        final futureResult = computed.future.catchError((e) => 'caught error');

        await Future.delayed(Duration(milliseconds: 10));
        dispose(); // Cancel computation

        final result = await futureResult;
        expect(result, 'caught error');
      });
    });

    group("reactive behavior", () {
      mytest('computation does not re-execute on its own', () async {
        int executionCount = 0;
        final computed = ComputedFuture.nonReactive((state) async {
          executionCount++;
          await Future.delayed(Duration(milliseconds: 10));
          return executionCount;
        });

        effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 50));
        expect(executionCount, 1);
        expect(computed.value.value, 1);

        // Wait more and verify it doesn't re-execute
        await Future.delayed(Duration(milliseconds: 50));
        expect(executionCount, 1);
        expect(computed.value.value, 1);
      });

      mytest(
        'accessing value multiple times does not restart computation',
        () async {
          int executionCount = 0;
          final computed = ComputedFuture.nonReactive((state) async {
            executionCount++;
            await Future.delayed(Duration(milliseconds: 10));
            return 'result';
          });

          effect(() {
            computed.value; // First access
          });

          await Future.delayed(Duration(milliseconds: 20));

          effect(() {
            computed.value; // Second access
          });

          await Future.delayed(Duration(milliseconds: 20));
          expect(executionCount, 1); // Should only execute once
        },
      );
    });

    group("edge cases", () {
      mytest('computation returning null', () async {
        final computed = ComputedFuture.nonReactive<String?>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return null;
        });

        effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 20));
        expect(computed.value.value, null);
      });

      mytest('computation with immediate return', () async {
        final computed = ComputedFuture.nonReactive((state) async {
          return 'immediate';
        });

        effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 10));
        expect(computed.value.value, 'immediate');
      });

      mytest('dispose prevents computation start in lazy mode', () async {
        bool computationStarted = false;
        final computed = ComputedFuture.nonReactive((state) async {
          computationStarted = true;
          return 'result';
        }); // lazy by default

        computed.dispose();

        // Should not be able to access value after disposal
        expect(computed.disposed, true);

        // Try to trigger computation - this should not start the computation
        // since the signal is disposed
        await Future.delayed(Duration(milliseconds: 20));
        expect(computationStarted, false);
      });
    });
  });

  group("lazy", () {
    mytest('no defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture(number, (state, input) async {
        return input * input;
      });
      expect(squared.peek(), AsyncState.loading());
      final events = [];
      effect(() {
        events.add(squared.value);
      });
      await Future.delayed(Duration(milliseconds: 100));

      expect(events, [AsyncState.loading(), AsyncState.data(4)]);
    });
  });
  group("eager", () {
    mytest('no defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture(number, (state, input) async {
        return input * input;
      }, lazy: false);
      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.peek(), AsyncState.data(4));
    });
  });
  group("autoDispose", () {
    mytest('true', () async {
      final number = signal(2);
      final events = [];
      final squared = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        final result = input * input;
        if (state.isCanceled) {
          throw Exception();
        }
        events.add(result);
        return result;
      }, autoDispose: true);

      final future = squared.future.onError((error, stackTrace) => -1);

      final dispose = effect(() {
        squared.value;
      });
      await Future.delayed(Duration(milliseconds: 10));
      dispose();
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, []);

      expect(await future, -1);
    });
    mytest('false', () async {
      final number = signal(2);
      final events = [];
      final squared = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        final result = input * input;
        if (state.isCanceled) {
          throw Exception();
        }
        events.add(result);
        return result;
      }, autoDispose: false);
      bool futureThrew = false;
      final future = squared.future.onError((error, stackTrace) {
        futureThrew = true;
        return 0;
      });
      final dispose = effect(() {
        squared.value;
      });
      await Future.delayed(Duration(milliseconds: 10));
      dispose();
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, [4]);
      expectLater(await future, 4);
      expect(futureThrew, false);
    });
  });

  group("error handling", () {
    mytest('lazy with error', () async {
      final number = signal(2);
      final squared = ComputedFuture(number, (state, input) async {
        if (input == 4) {
          throw Exception('Test error');
        }
        return input * input;
      });

      expect(squared.peek(), AsyncState.loading());
      final events = [];
      effect(() {
        events.add(squared.value);
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(events.length, 2);
      expect(events[0], AsyncState.loading());
      expect(events[1], AsyncState.data(4));

      // Trigger error
      number.value = 4;
      await Future.delayed(Duration(milliseconds: 100));

      expect(events.length, 4);
      expect(events[2], AsyncState.loading());
      expect(events[3].hasError, true);
      expect(events[3].error, isA<Exception>());
    });

    mytest('eager with error', () async {
      final number = signal(4);
      final squared = ComputedFuture(number, (state, input) async {
        if (input == 4) {
          throw Exception('Test error');
        }
        return input * input;
      }, lazy: false);

      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.peek().hasError, true);
      expect(squared.peek().error, isA<Exception>());
    });

    mytest('error recovery', () async {
      final number = signal(4);
      final squared = ComputedFuture(number, (state, input) async {
        if (input == 4) {
          throw Exception('Test error');
        }
        return input * input;
      });

      final events = <AsyncState>[];
      effect(() {
        events.add(squared.value);
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(events.last.hasError, true);

      // Recover from error
      number.value = 2;
      await Future.delayed(Duration(milliseconds: 100));
      expect(events.last, AsyncState.data(4));
    });
  });

  group("cancellation behavior", () {
    mytest('signal change cancels previous computation', () async {
      final number = signal(1);
      final events = <String>[];

      final computed = ComputedFuture(number, (state, input) async {
        events.add('start_$input');
        await Future.delayed(Duration(milliseconds: 50));

        if (state.isCanceled) {
          events.add('canceled_$input');
          return -1;
        }

        events.add('complete_$input');
        return input * 2;
      });

      effect(() {
        computed.value;
      });

      await Future.delayed(Duration(milliseconds: 25));
      number.value = 2; // This should cancel the previous computation
      await Future.delayed(Duration(milliseconds: 100));

      expect(events, contains('start_1'));
      expect(events, contains('canceled_1'));
      expect(events, contains('start_2'));
      expect(events, contains('complete_2'));
    });

    mytest('onCancel callback is triggered on signal change', () async {
      final number = signal(1);
      final cancelEvents = <String>[];

      final computed = ComputedFuture(number, (state, input) async {
        state.onCancel(() {
          cancelEvents.add('cleanup_$input');
        });

        await Future.delayed(Duration(milliseconds: 30));
        return input * 2;
      });

      effect(() {
        computed.value;
      });

      await Future.delayed(Duration(milliseconds: 15));
      number.value = 2; // This should trigger onCancel for input 1
      await Future.delayed(Duration(milliseconds: 50));

      expect(cancelEvents, contains('cleanup_1'));
    });
  });

  group("future access", () {
    mytest('future property returns correct value', () async {
      final number = signal(3);
      final computed = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        return input * 3;
      });

      effect(() {
        computed.value; // Trigger computation
      });

      final result = await computed.future;
      expect(result, 9);
    });

    mytest('future property handles errors', () async {
      final number = signal(5);
      final computed = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        throw Exception('Future error');
      });

      effect(() {
        computed.value; // Trigger computation
      });

      try {
        await computed.future;
        // ignore: dead_code
        fail('Expected exception to be thrown');
      } catch (e) {
        expect(e, isA<Exception>());
        expect(e.toString(), contains('Future error'));
      }
    });
  });

  group("signal updates", () {
    mytest('signal change triggers recomputation', () async {
      final number = signal(1);
      int computationCount = 0;

      final computed = ComputedFuture(number, (state, input) async {
        computationCount++;
        await Future.delayed(Duration(milliseconds: 10));
        return input * 2;
      });

      effect(() {
        computed.value;
      });

      await Future.delayed(Duration(milliseconds: 50));
      expect(computationCount, 1);
      expect(computed.value.value, 2);

      number.value = 3;
      await Future.delayed(Duration(milliseconds: 50));
      expect(computationCount, 2);
      expect(computed.value.value, 6);
    });

    mytest('rapid signal changes cancel previous computations', () async {
      final number = signal(1);
      final events = <String>[];

      final computed = ComputedFuture(number, (state, input) async {
        events.add('start_$input');
        await Future.delayed(Duration(milliseconds: 30));

        if (state.isCanceled) {
          events.add('canceled_$input');
          return -1;
        }

        events.add('complete_$input');
        return input * 2;
      });

      effect(() {
        computed.value;
      });

      // Rapidly change the signal
      number.value = 2;
      await Future.delayed(Duration(milliseconds: 5));
      number.value = 3;
      await Future.delayed(Duration(milliseconds: 5));
      number.value = 4;

      await Future.delayed(Duration(milliseconds: 100));

      // Should see cancellations for 1, 2, 3 and completion for 4
      expect(events.where((e) => e.startsWith('start_')).length, 4);
      expect(events.where((e) => e.startsWith('canceled_')).length, 3);
      expect(events, contains('complete_4'));
    });
  });

  group("edge cases", () {
    mytest('null input handling', () async {
      final nullableSignal = signal<String?>(null);

      final computed = ComputedFuture(nullableSignal, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        return input?.length ?? 0;
      });

      effect(() {
        computed.value;
      });

      await Future.delayed(Duration(milliseconds: 50));
      expect(computed.value.value, 0);

      nullableSignal.value = 'hello';
      await Future.delayed(Duration(milliseconds: 50));
      expect(computed.value.value, 5);
    });

    mytest('dispose prevents new computations', () async {
      final number = signal(1);
      int computationCount = 0;

      final computed = ComputedFuture(number, (state, input) async {
        computationCount++;
        await Future.delayed(Duration(milliseconds: 10));
        return input * 2;
      });

      effect(() {
        computed.value;
      });

      await Future.delayed(Duration(milliseconds: 50));
      expect(computationCount, 1);

      computed.dispose();

      // Try to trigger new computation
      number.value = 2;
      await Future.delayed(Duration(milliseconds: 50));

      // Should not have triggered new computation
      expect(computationCount, 1);
      expect(computed.disposed, true);
    });
  });

  group("chained computations", () {
    test('old future chains to final result after mid-flight changes', () async {
      final number = signal(1);
      final events = <String>[]; // Track computation phases for debugging

      final computed = ComputedFuture(number, (state, input) async {
        events.add('start_$input');
        await Future.delayed(Duration(milliseconds: 20)); // Simulate async work

        if (state.isCanceled) {
          events.add('canceled_$input');
          // Don't complete with -1; let chaining handle it
          throw Exception('Should not resolve canceled'); // But impl skips this
        }

        events.add('complete_$input');
        return input * 10; // Multiply for easy verification
      });

      effect(() {
        computed.value; // Subscribe to trigger computations
      });

      // Obtain "old" future before any changes (initial compute starts)
      final oldFuture = computed.future;
      await Future.delayed(Duration(milliseconds: 5)); // Partial initial work

      // Mid-flight changes: cancel initial and intermediates
      number.value = 2; // Change 1: starts 2nd compute, cancels 1st

      await Future.delayed(Duration(milliseconds: 5));
      number.value = 3; // Change 2: starts 3rd (final), cancels 2nd

      await Future.delayed(Duration(milliseconds: 50)); // Let final complete

      // Old future should chain to FINAL result (30), not initial (10) or intermediate (20)
      expect(await oldFuture, 30);

      // Latest direct access also gets final
      expect(computed.value.value, 30);
      print(events);

      // Verify events: starts for all, cancels for all but last, no 'complete' for canceled
      expect(events.where((e) => e.startsWith('start_')).toList(), [
        'start_1',
        'start_2',
        'start_3',
      ]);
      expect(events.where((e) => e.startsWith('canceled_')).toList(), [
        'canceled_1',
        'canceled_2',
      ]);
      expect(events, contains('complete_3'));
      expect(events, isNot(contains('complete_1')));
      expect(events, isNot(contains('complete_2')));
      print(events);
    });
    mytest('chain with unhandled upstream error', () async {
      final number = signal(5); // Triggers upstream error

      final processed = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 5) throw Exception('Upstream error');
        return input * 2;
      });

      final result = ComputedFuture(processed, (state, _) async {
        await Future.delayed(Duration(milliseconds: 10));
        // Assume success - this should throw on requireValue
        final processedValue = await processed.future;
        return processedValue + 10;
      });

      effect(() {
        result.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.hasError, true);
      expect(result.value.error.toString(), contains('Upstream error'));

      // Recover upstream
      number.value = 3;
      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.value, 16); // (3*2) + 10
    });
    mytest('simple chain: number -> doubled -> squared', () async {
      final number = signal(3);

      // First computation: double the number
      final doubled = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        return input * 2;
      });

      // Second computation: square the doubled result
      final squared = ComputedFuture(doubled, (state, doubledState) async {
        await Future.delayed(Duration(milliseconds: 10));
        final doubledValue = doubledState.requireValue;
        return doubledValue * doubledValue;
      });

      effect(() {
        squared.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.value.value, 36); // (3 * 2) ^ 2 = 36
    });
    mytest(
      'simple chain: number -> doubled -> squared with rapid changes',
      () async {
        final number = signal(3);
        final values = <int?>[];

        // First computation: double the number
        final doubled = ComputedFuture(number, (state, input) async {
          await Future.delayed(Duration(milliseconds: 100));
          return input * 2;
        });

        // Second computation: square the doubled result
        final squared = ComputedFuture(doubled, (state, doubledState) async {
          await Future.delayed(Duration(milliseconds: 100));
          final doubledValue = doubledState.requireValue;
          return doubledValue * doubledValue;
        });

        effect(() {
          values.add(squared.value.value);
        });

        await Future.delayed(Duration(milliseconds: 50));
        number.value = 4;
        await Future.delayed(Duration(milliseconds: 100));
        number.value = 5;
        await Future.delayed(Duration(milliseconds: 300));
        expect(values, [null, null, null, 100]);
      },
    );

    mytest('chain with error propagation', () async {
      final number = signal(5);

      // First computation: throw error for certain values
      final processed = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 5) {
          throw Exception('Processing error');
        }
        return input * 2;
      });

      // Second computation: depends on first
      final result = ComputedFuture(processed, (state, processedState) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (processedState.hasError) {
          throw Exception('Chain error: ${processedState.error}');
        }
        final processedValue = processedState.requireValue;
        return processedValue + 10;
      });

      effect(() {
        result.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.hasError, true);
      expect(result.value.error.toString(), contains('Chain error'));
    });

    mytest('chain with cancellation', () async {
      final number = signal(2);
      final events = <String>[];

      // First computation
      final doubled = ComputedFuture(number, (state, input) async {
        events.add('doubled_start_$input');
        await Future.delayed(Duration(milliseconds: 30));

        if (state.isCanceled) {
          events.add('doubled_canceled_$input');
          return -1;
        }

        events.add('doubled_complete_$input');
        return input * 2;
      });

      // Second computation
      final squared = ComputedFuture(doubled, (state, doubledState) async {
        final doubledValue = doubledState.requireValue;
        events.add('squared_start_$doubledValue');
        await Future.delayed(Duration(milliseconds: 30));

        if (state.isCanceled) {
          events.add('squared_canceled_$doubledValue');
          return -1;
        }

        events.add('squared_complete_$doubledValue');
        return doubledValue * doubledValue;
      });

      effect(() {
        squared.value;
      });

      await Future.delayed(Duration(milliseconds: 20));
      number.value = 3; // Cancel previous computations
      await Future.delayed(Duration(milliseconds: 100));

      // Should see cancellations for the first computation
      expect(events, contains('doubled_canceled_2'));
      expect(events, contains('doubled_start_3'));
      expect(events, contains('doubled_complete_3'));
      expect(events, contains('squared_start_6'));
      expect(events, contains('squared_complete_6'));
    });

    mytest('multiple dependent computations', () async {
      final number = signal(2);

      // Chain: number -> doubled -> tripled -> final
      final doubled = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 5));
        return input * 2;
      });

      final tripled = ComputedFuture(doubled, (state, doubledState) async {
        await Future.delayed(Duration(milliseconds: 5));
        final doubledValue = doubledState.requireValue;
        return doubledValue * 3;
      });

      final finalResult = ComputedFuture(tripled, (state, tripledState) async {
        await Future.delayed(Duration(milliseconds: 5));
        final tripledValue = tripledState.requireValue;
        return tripledValue + 10;
      });

      effect(() {
        finalResult.value;
      });

      await Future.delayed(Duration(milliseconds: 50));
      expect(finalResult.value.value, 22); // (2 * 2 * 3) + 10 = 22
    });

    mytest('chain with different input types', () async {
      final textSignal = signal('hello');

      // First: get length
      final length = ComputedFuture(textSignal, (state, text) async {
        await Future.delayed(Duration(milliseconds: 10));
        return text.length;
      });

      // Second: create list of that length
      final list = ComputedFuture(length, (state, lengthState) async {
        await Future.delayed(Duration(milliseconds: 10));
        final lengthValue = lengthState.requireValue;
        return List.generate(lengthValue, (i) => i);
      });

      // Third: sum the list
      final sum = ComputedFuture(list, (state, listState) async {
        await Future.delayed(Duration(milliseconds: 10));
        final listValue = listState.requireValue;
        return listValue.reduce((a, b) => a + b);
      });

      effect(() {
        sum.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(sum.value.value, 10); // [0,1,2,3,4] sum = 10

      textSignal.value = 'hi';
      await Future.delayed(Duration(milliseconds: 100));
      expect(sum.value.value, 1); // [0,1] sum = 1
    });

    mytest('chain with async error recovery', () async {
      final number = signal(4);

      // First computation: throws error for 4
      final processed = ComputedFuture(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 4) {
          throw Exception('Invalid input');
        }
        return input * 2;
      });

      // Second computation: handles the error gracefully
      final result = ComputedFuture(processed, (state, processedState) async {
        await Future.delayed(Duration(milliseconds: 10));
        final processedValue = processedState.requireValue;
        return processedValue + 5;
      });

      effect(() {
        result.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.hasError, true);

      // Recover by changing input
      number.value = 3;
      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.value, 11); // (3 * 2) + 5 = 11
    });
  });
  mytest('multiple onCancel callbacks', () async {
    final number = signal(1);
    final cancelEvents = <String>[];

    final computed = ComputedFuture(number, (state, input) async {
      state.onCancel(
        () => cancelEvents.add('cleanup1_$input'),
      ); // First registered
      state.onCancel(() => cancelEvents.add('cleanup2_$input')); // Second
      state.onCancel(() => cancelEvents.add('cleanup3_$input')); // Third

      await Future.delayed(Duration(milliseconds: 20));
      if (state.isCanceled) {
        cancelEvents.add('canceled_inside_fn_$input');
        return -1;
      }
      return input * 2;
    });

    effect(() {
      computed.value;
    });

    await Future.delayed(Duration(milliseconds: 25));
    number.value = 2; // Triggers cancel for input=1

    await Future.delayed(Duration(milliseconds: 50));
    expect(cancelEvents, ['cleanup1_1', 'cleanup2_1', 'cleanup3_1']);
    expect(
      cancelEvents,
      isNot(contains('canceled_inside_fn_1')),
    ); // Didn't finish due to cancel
  });
  mytest('error in onCancel has no effect', () async {
    final number = signal(1);
    final cancelEvents = <String>[];
    bool chainContinued = false;

    final computed = ComputedFuture(number, (state, input) async {
      state.onCancel(() {
        cancelEvents.add('cleanup1_$input');
        throw Exception('Error in first callback'); // Throws here
      });
      state.onCancel(() {
        cancelEvents.add('cleanup2_$input');
        chainContinued = true; // Check if chain survives throw
      });

      await Future.delayed(Duration(milliseconds: 20));
      return input * 2;
    });

    effect(() {
      computed.value;
    });

    await Future.delayed(Duration(milliseconds: 50));
    number.value = 2;
    await Future.delayed(Duration(milliseconds: 50));
    expect(cancelEvents, ['cleanup1_1', 'cleanup2_1']);
    expect(chainContinued, true);
  });
}
