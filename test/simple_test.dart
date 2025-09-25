import 'dart:async';

import 'package:signal_async/signals_async.dart';
import 'package:signals/signals.dart' hide computedAsync, computedFrom;
import 'package:test/test.dart';

void main() async {
  group("lazy", () {
    test('no defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
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
    test('with defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
        return input * input;
      }, initialValue: 2);
      expect(squared.peek(), AsyncState.data(2));
      final events = [];
      effect(() {
        events.add(squared.value);
      });
      await Future.delayed(Duration(milliseconds: 100));
      expect(events, [AsyncState.data(2), AsyncState.data(4)]);
    });
  });
  group("eager", () {
    test('no defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
        return input * input;
      }, lazy: false);
      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.peek(), AsyncState.data(4));
    });
    test('with defaults', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(
        number,
        (state, input) async {
          return input * input;
        },
        initialValue: 2,
        lazy: false,
      );
      final events = [];
      effect(() {
        events.add(squared.value);
      });
      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.peek(), AsyncState.data(4));
      expect(events, [AsyncState.data(2), AsyncState.data(4)]);
    });
  });
  group("autoDispose", () {
    test('true', () async {
      final number = signal(2);
      final events = [];
      final squared = ComputedFuture.withSignal(number, (state, input) async {
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
    test('false', () async {
      final number = signal(2);
      final events = [];
      final squared = ComputedFuture.withSignal(number, (state, input) async {
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
    test('eager with initial and error', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(
        number,
        (state, input) async {
          throw Exception('Test error'); // Always errors
        },
        initialValue: 4,
        lazy: false,
      );

      // Should briefly have initial, then error (no loading if sync error, but assume async)
      final events = [];
      effect(() {
        events.add(squared.value);
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(events.length, 3);
      expect(events[0], AsyncState.data(4)); // Initial
      expect(events[1], AsyncState.loading()); // Eager load
      expect(events[2].hasError, true);
      expect(squared.peek().hasError, true);
    });
    test('lazy with initial and error', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
        if (input == 2) {
          throw Exception('Test error');
        }
        return input * input;
      }, initialValue: 4); // Initial before any error

      expect(squared.peek(), AsyncState.data(4));
      final events = [];
      effect(() {
        events.add(squared.value);
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(events.length, 3);
      expect(events[0], AsyncState.data(4)); // Starts with initial
      expect(events[1], AsyncState.loading()); // Then loads
      expect(events[2].hasError, true);
      expect(events[2].error, isA<Exception>());

      // Recover to success
      number.value = 3;
      await Future.delayed(Duration(milliseconds: 100));
      expect(events.last, AsyncState.data(9));
    });
    test('lazy with error', () async {
      final number = signal(2);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
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
      print(events[3]);
      expect(events[3].hasError, true);
      expect(events[3].error, isA<Exception>());
    });

    test('eager with error', () async {
      final number = signal(4);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
        if (input == 4) {
          throw Exception('Test error');
        }
        return input * input;
      }, lazy: false);

      await Future.delayed(Duration(milliseconds: 100));
      expect(squared.peek().hasError, true);
      expect(squared.peek().error, isA<Exception>());
    });

    test('error recovery', () async {
      final number = signal(4);
      final squared = ComputedFuture.withSignal(number, (state, input) async {
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
    test('signal change cancels previous computation', () async {
      final number = signal(1);
      final events = <String>[];

      final computed = ComputedFuture.withSignal(number, (state, input) async {
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

    test('onCancel callback is triggered on signal change', () async {
      final number = signal(1);
      final cancelEvents = <String>[];

      final computed = ComputedFuture.withSignal(number, (state, input) async {
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
    test('future property returns correct value', () async {
      final number = signal(3);
      final computed = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        return input * 3;
      });

      effect(() {
        computed.value; // Trigger computation
      });

      final result = await computed.future;
      expect(result, 9);
    });

    test('future property handles errors', () async {
      final number = signal(5);
      final computed = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 20));
        throw Exception('Future error');
      });

      effect(() {
        computed.value; // Trigger computation
      });

      try {
        await computed.future;
        fail('Expected exception to be thrown');
      } catch (e) {
        expect(e, isA<Exception>());
        expect(e.toString(), contains('Future error'));
      }
    });
  });

  group("signal updates", () {
    test('signal change triggers recomputation', () async {
      final number = signal(1);
      int computationCount = 0;

      final computed = ComputedFuture.withSignal(number, (state, input) async {
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

    test('rapid signal changes cancel previous computations', () async {
      final number = signal(1);
      final events = <String>[];

      final computed = ComputedFuture.withSignal(number, (state, input) async {
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
    // test('access after dispose', () async {
    //   final number = signal(1);
    //   final computed = ComputedFuture.withSignal(number, (state, input) async {
    //     await Future.delayed(Duration(milliseconds: 10));
    //     return input * 2;
    //   });

    //   effect(() {
    //     computed.value;
    //   });
    //   await Future.delayed(Duration(milliseconds: 50)); // Initial compute
    //   expect(computed.value.value, 2);

    //   computed.dispose();
    //   expect(computed.disposed, true);
    //   expect(
    //     computed.peek(),
    //     AsyncState.loading(),
    //   ); // Or whatever your disposed state is; adjust assertion
    //   expect(
    //     () => computed.value,
    //     throwsStateError,
    //   ); // Or returns disposed state - test impl behavior

    //   // future should not hang/complete new values
    //   // try {
    //   //   await computed.future.timeout(Duration(milliseconds: 50));
    //   //   fail('Expected timeout or error after dispose');
    //   // } catch (e) {
    //   //   expect(
    //   //     e,
    //   //     isA<TimeoutException>(),
    //   //   ); // Or handle as per impl (e.g., completes with null/error)
    //   // }

    //   // Change signal - no recompute
    //   number.value = 3;
    //   await Future.delayed(Duration(milliseconds: 50));
    //   expect(computed.disposed, true); // Still disposed
    // });

    test('null input handling', () async {
      final nullableSignal = signal<String?>(null);

      final computed = ComputedFuture.withSignal(nullableSignal, (
        state,
        input,
      ) async {
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

    test('dispose prevents new computations', () async {
      final number = signal(1);
      int computationCount = 0;

      final computed = ComputedFuture.withSignal(number, (state, input) async {
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
    test('chain with unhandled upstream error', () async {
      final number = signal(5); // Triggers upstream error

      final processed = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 5) throw Exception('Upstream error');
        return input * 2;
      });

      final result = ComputedFuture.withSignal(processed, (
        state,
        processedState,
      ) async {
        await Future.delayed(Duration(milliseconds: 10));
        // Assume success - this should throw on requireValue
        final processedValue = processedState.requireValue;
        return processedValue + 10;
      });

      effect(() {
        result.value;
      });

      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.hasError, true);
      expect(
        result.value.error.toString(),
        contains('Upstream error'),
      ); // Propagated via requireValue throw

      // Recover upstream
      number.value = 3;
      await Future.delayed(Duration(milliseconds: 100));
      expect(result.value.value, 16); // (3*2) + 10
    });
    test('simple chain: number -> doubled -> squared', () async {
      final number = signal(3);

      // First computation: double the number
      final doubled = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        return input * 2;
      });

      // Second computation: square the doubled result
      final squared = ComputedFuture.withSignal(doubled, (
        state,
        doubledState,
      ) async {
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

    test('chain with error propagation', () async {
      final number = signal(5);

      // First computation: throw error for certain values
      final processed = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 5) {
          throw Exception('Processing error');
        }
        return input * 2;
      });

      // Second computation: depends on first
      final result = ComputedFuture.withSignal(processed, (
        state,
        processedState,
      ) async {
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

    test('chain with cancellation', () async {
      final number = signal(2);
      final events = <String>[];

      // First computation
      final doubled = ComputedFuture.withSignal(number, (state, input) async {
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
      final squared = ComputedFuture.withSignal(doubled, (
        state,
        doubledState,
      ) async {
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

    test('multiple dependent computations', () async {
      final number = signal(2);

      // Chain: number -> doubled -> tripled -> final
      final doubled = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 5));
        return input * 2;
      });

      final tripled = ComputedFuture.withSignal(doubled, (
        state,
        doubledState,
      ) async {
        await Future.delayed(Duration(milliseconds: 5));
        final doubledValue = doubledState.requireValue;
        return doubledValue * 3;
      });

      final finalResult = ComputedFuture.withSignal(tripled, (
        state,
        tripledState,
      ) async {
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

    test('chain with different input types', () async {
      final textSignal = signal('hello');

      // First: get length
      final length = ComputedFuture.withSignal(textSignal, (state, text) async {
        await Future.delayed(Duration(milliseconds: 10));
        return text.length;
      });

      // Second: create list of that length
      final list = ComputedFuture.withSignal(length, (
        state,
        lengthState,
      ) async {
        await Future.delayed(Duration(milliseconds: 10));
        final lengthValue = lengthState.requireValue;
        return List.generate(lengthValue, (i) => i);
      });

      // Third: sum the list
      final sum = ComputedFuture.withSignal(list, (state, listState) async {
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

    test('chain with async error recovery', () async {
      final number = signal(4);

      // First computation: throws error for 4
      final processed = ComputedFuture.withSignal(number, (state, input) async {
        await Future.delayed(Duration(milliseconds: 10));
        if (input == 4) {
          throw Exception('Invalid input');
        }
        return input * 2;
      });

      // Second computation: handles the error gracefully
      final result = ComputedFuture.withSignal(processed, (
        state,
        processedState,
      ) async {
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
  group('original FutureSignal tests', () {
    return;
    test('computedAsync', () async {
      Future<int> future() async {
        await Future.delayed(const Duration(milliseconds: 5));
        return 10;
      }

      final signal = ComputedFuture((state) => future());
      expect(signal.peek().isLoading, true);

      final completer = Completer<int>();
      effect(() {
        signal.value;
        if (signal.value.hasValue) {
          completer.complete(signal.peek().requireValue);
        }
      });
      final result = await completer.future;

      expect(result, 10);
    });

    test('computedFrom', () async {
      Future<int> future(List<int> ids) async {
        await Future.delayed(const Duration(milliseconds: 5));
        return 10;
      }

      final id = signal(1);
      final s = ComputedFuture.withSignal(id, (state, ids) => future([ids]));
      expect(s.peek().isLoading, true);

      final completer = Completer<int>();
      effect(() {
        s.value;
        if (s.value.hasValue) {
          completer.complete(s.peek().requireValue);
        }
      });
      final result = await completer.future;

      expect(result, 10);
    });

    test('check repeated calls', () async {
      int calls = 0;

      Future<int> future() async {
        calls++;
        await Future.delayed(const Duration(milliseconds: 5));
        return 10;
      }

      final signal = ComputedFuture((state) => future());
      expect(signal.peek().isLoading, true);
      expect(calls, 1);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);
    });

    test('check reload calls', () async {
      int calls = 0;

      Future<int> future() async {
        calls++;
        await Future.delayed(const Duration(milliseconds: 5));
        return 10;
      }

      final signal = ComputedFuture((state) => future());
      expect(signal.peek().isLoading, true);
      expect(calls, 1);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);

      await signal.reload();

      expect(calls, 2);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);
    });

    test('check refresh calls', () async {
      int calls = 0;

      Future<int> future() async {
        calls++;
        await Future.delayed(const Duration(milliseconds: 5));
        return 10;
      }

      final signal = ComputedFuture((state) => future());
      expect(signal.peek().isLoading, true);
      expect(calls, 1);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);

      await signal.future;

      expect(calls, 1);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);

      await signal.refresh();

      expect(calls, 2);
      expect(signal.value.value, 10);
      expect(signal.value.error, null);
    });

    test('dependencies', () async {
      final prefix = signal('a');
      final val = signal(0);
      final f = ComputedFuture.withSignal(computed(() => (prefix(), val())), (
        state,
        input,
      ) async {
        final (p, v) = input;
        await Future.delayed(const Duration(seconds: 1));
        return '$p$v';
      });
      expect(f.peek().isLoading, true);

      var result = await f.future;

      expect(result, 'a0');

      prefix.value = 'b';
      await f.future;
      result = f.requireValue;

      expect(result, 'b0');
    });
  });
}
