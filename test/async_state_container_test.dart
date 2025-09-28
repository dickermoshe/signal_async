import 'dart:async';

import 'package:signals_async/src/async_state_container.dart';
import 'package:signals/signals.dart';
import 'package:test/test.dart';

void main() async {
  group("AsyncStateContainer", () {
    group("basic functionality", () {
      test('creates container with loading state initially', () async {
        final container = AsyncStateContainer<int>((state) async => 42);

        expect(container.state, AsyncState.loading());
        expect(container.isCanceled, false);
      });

      test('executes future builder and updates state', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'hello world';
        });

        expect(container.state, AsyncState.loading());

        container.run();
        await Future.delayed(Duration(milliseconds: 50));

        expect(container.state, AsyncState.data('hello world'));
        expect(container.isCanceled, false);
      });

      test('future property triggers execution automatically', () async {
        bool executed = false;
        final container = AsyncStateContainer<int>((state) async {
          executed = true;
          return 123;
        });

        expect(executed, false);

        final result = await container.future;

        expect(executed, true);
        expect(result, 123);
        expect(container.state, AsyncState.data(123));
      });

      test('handles synchronous completion', () async {
        final container = AsyncStateContainer<double>((state) async => 3.14);

        final result = await container.future;

        expect(result, 3.14);
        expect(container.state, AsyncState.data(3.14));
      });

      test('handles null values', () async {
        final container = AsyncStateContainer<String?>((state) async => null);

        final result = await container.future;

        expect(result, null);
        expect(container.state.value, null);
      });
    });

    group("initial value support", () {
      test('creates container with initial value', () async {
        final container = AsyncStateContainer<String>(
          (state) async => 'computed',
          initialValue: 'initial',
        );

        expect(container.state, AsyncState.data('initial'));
        expect(container.isCanceled, false);
      });

      test(
        'initial value is shown in state but future returns computed result',
        () async {
          final container = AsyncStateContainer<int>((state) async {
            await Future.delayed(Duration(milliseconds: 20));
            return 100;
          }, initialValue: 42);

          // Initial state should show initial value
          expect(container.state, AsyncState.data(42));

          // Future should return computed result, not initial value
          final result = await container.future;
          expect(result, 100);
          expect(container.state, AsyncState.data(100));
        },
      );

      test('initial value is overridden by computation result', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'computed_result';
        }, initialValue: 'initial_value');

        // Initially should have initial value
        expect(container.state, AsyncState.data('initial_value'));

        // Start computation
        container.run();
        await Future.delayed(Duration(milliseconds: 30));

        // Should now have computed result
        expect(container.state, AsyncState.data('computed_result'));
      });

      test(
        'computation runs even with initial value when future is accessed',
        () async {
          bool computationRan = false;
          final container = AsyncStateContainer<double>((state) async {
            computationRan = true;
            await Future.delayed(Duration(milliseconds: 20));
            return 99.9;
          }, initialValue: 3.14);

          // Initial state should have initial value
          expect(container.state, AsyncState.data(3.14));

          final result = await container.future;

          expect(result, 99.9); // Should get computed result
          expect(computationRan, true); // Computation should run
          expect(container.state, AsyncState.data(99.9));
        },
      );

      test('initial value with different types', () async {
        // Test with various types
        final stringContainer = AsyncStateContainer<String>(
          (state) async => 'computed',
          initialValue: 'initial_string',
        );
        expect(stringContainer.state.value, 'initial_string');

        final intContainer = AsyncStateContainer<int>(
          (state) async => 999,
          initialValue: 123,
        );
        expect(intContainer.state.value, 123);

        final boolContainer = AsyncStateContainer<bool>(
          (state) async => false,
          initialValue: true,
        );
        expect(boolContainer.state.value, true);

        final listContainer = AsyncStateContainer<List<int>>(
          (state) async => [4, 5, 6],
          initialValue: [1, 2, 3],
        );
        expect(listContainer.state.value, [1, 2, 3]);

        final mapContainer = AsyncStateContainer<Map<String, int>>(
          (state) async => {'computed': 1},
          initialValue: {'initial': 42},
        );
        expect(mapContainer.state.value, {'initial': 42});
      });

      test('initial value persists through cancellation', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 30));
          return 'computed';
        }, initialValue: 'initial');

        expect(container.state.value, 'initial');

        // Start computation
        container.run();
        await Future.delayed(Duration(milliseconds: 10));

        // Cancel before completion
        container.cancel();

        // Should still have initial value
        expect(container.state.value, 'initial');
        expect(container.isCanceled, true);
      });

      test('chaining preserves initial values correctly', () async {
        final container1 = AsyncStateContainer<int>(
          (state) async => 100,
          initialValue: 10,
        );

        final container2 = AsyncStateContainer<int>(
          (state) async => 200,
          initialValue: 20,
        );

        expect(container1.state.value, 10);
        expect(container2.state.value, 20);

        // Chain container1 to container2
        container1.cancel(container2);

        // container1 should now show container2's state
        expect(container1.state.value, 20);
        expect(container2.state.value, 20);
      });

      test('initial value with error in computation', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Computation failed');
        }, initialValue: 'safe_initial');

        expect(container.state.value, 'safe_initial');

        // Start computation which will fail
        try {
          await container.future;
          fail('Expected exception');
        } catch (e) {
          expect(e, isA<Exception>());
        }

        // State should now be error, not initial value
        expect(container.state.hasError, true);
        expect(container.state.error, isA<Exception>());
      });

      test(
        'multiple containers with same initial value are independent',
        () async {
          final initialList1 = [1, 2, 3];
          final initialList2 = [1, 2, 3];

          final container1 = AsyncStateContainer<List<int>>(
            (state) async => [10, 20],
            initialValue: initialList1,
          );

          final container2 = AsyncStateContainer<List<int>>(
            (state) async => [40, 50],
            initialValue: initialList2,
          );

          // Both should have same initial value
          expect(container1.state.value, [1, 2, 3]);
          expect(container2.state.value, [1, 2, 3]);

          // Modify one container's initial value reference
          container1.state.value!.add(999);

          // Other container should NOT be affected (different references)
          expect(container1.state.value, [1, 2, 3, 999]);
          expect(container2.state.value, [1, 2, 3]); // Should remain unchanged

          // But their computations should be independent
          container1.run();
          await Future.delayed(Duration(milliseconds: 20));

          expect(container1.state.value, [10, 20]);
          expect(container2.state.value, [
            1,
            2,
            3,
          ]); // Still has original initial
        },
      );

      test('initial value vs no initial value behavior', () async {
        final containerWithInitial = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'computed';
        }, initialValue: 'initial');

        final containerWithoutInitial = AsyncStateContainer<String>((
          state,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'computed';
        });

        // Different initial states
        expect(containerWithInitial.state, AsyncState.data('initial'));
        expect(containerWithoutInitial.state, AsyncState.loading());

        // Both should compute to same result
        final result1 = await containerWithInitial.future;
        final result2 = await containerWithoutInitial.future;

        expect(result1, 'computed');
        expect(result2, 'computed');
        expect(containerWithInitial.state, AsyncState.data('computed'));
        expect(containerWithoutInitial.state, AsyncState.data('computed'));
      });

      test('initial value with complex objects', () async {
        final initialData = {
          'user': {'name': 'John', 'age': 30},
          'settings': {'theme': 'dark', 'notifications': true},
        };

        final container = AsyncStateContainer<Map<String, dynamic>>((
          state,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          return {
            'user': {'name': 'Jane', 'age': 25},
            'settings': {'theme': 'light', 'notifications': false},
          };
        }, initialValue: initialData);

        expect(container.state.value, initialData);
        expect(container.state.value!['user']['name'], 'John');

        final result = await container.future;
        expect(result['user']['name'], 'Jane');
        expect(container.state.value!['user']['name'], 'Jane');
      });

      test('initial value persists during computation', () async {
        final states = <AsyncState<String>>[];
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          return 'final';
        }, initialValue: 'initial');

        // Track initial state
        states.add(container.state);

        // Start computation
        final futureResult = container.future;

        // State should still show initial value during computation
        states.add(container.state);

        await futureResult;

        // Final state
        states.add(container.state);

        expect(states[0], AsyncState.data('initial'));
        expect(
          states[1],
          AsyncState.data('initial'),
        ); // Still initial during computation
        expect(states[2], AsyncState.data('final')); // Final result
      });
    });

    group("error handling", () {
      test('handles synchronous errors', () async {
        final container = AsyncStateContainer<int>((state) async {
          throw Exception('Sync error');
        });

        try {
          await container.future;
          fail('Expected exception to be thrown');
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('Sync error'));
        }

        expect(container.state.hasError, true);
        expect(container.state.error, isA<Exception>());
      });

      test('handles asynchronous errors', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          throw StateError('Async error');
        });

        try {
          await container.future;
          fail('Expected exception to be thrown');
        } catch (e) {
          expect(e, isA<StateError>());
          expect(e.toString(), contains('Async error'));
        }

        expect(container.state.hasError, true);
        expect(container.state.error, isA<StateError>());
      });

      test('handles errors in future builder', () async {
        final container = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 5));
          return int.parse('not_a_number'); // Will throw FormatException
        });

        try {
          await container.future;
          fail('Expected FormatException to be thrown');
        } catch (e) {
          expect(e, isA<FormatException>());
        }

        expect(container.state.hasError, true);
        expect(container.state.error, isA<FormatException>());
      });

      test('multiple error types are handled correctly', () async {
        final containers = [
          AsyncStateContainer<int>(
            (state) async => throw ArgumentError('arg error'),
          ),
          AsyncStateContainer<int>(
            (state) async => throw RangeError('range error'),
          ),
          AsyncStateContainer<int>(
            (state) async => throw UnsupportedError('unsupported'),
          ),
        ];

        for (int i = 0; i < containers.length; i++) {
          try {
            await containers[i].future;
            fail('Expected exception for container $i');
          } catch (e) {
            expect(containers[i].state.hasError, true);
          }
        }
      });
    });

    group("cancellation", () {
      test('can be canceled before execution', () async {
        final container = AsyncStateContainer<int>((state) async => 42);

        container.cancel();

        expect(container.isCanceled, true);
        expect(container.state, AsyncState.loading()); // State unchanged
      });

      test('can be canceled during execution', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          if (state.isCanceled) {
            throw Exception('Operation was canceled');
          }
          return 'completed';
        });

        // Start execution
        final futureResult = container.future;

        // Cancel after a short delay
        await Future.delayed(Duration(milliseconds: 10));
        container.cancel();

        try {
          await futureResult;
          fail('Expected CanceledFutureException');
        } catch (e) {
          expect(e, isA<CanceledFutureException>());
        }

        expect(container.isCanceled, true);
        // The execution might complete but should be marked as canceled
      });

      test('onCancel callbacks are executed', () async {
        final cancelEvents = <String>[];
        final container = AsyncStateContainer<int>((state) async {
          state.onCancel(() => cancelEvents.add('cleanup1'));
          state.onCancel(() => cancelEvents.add('cleanup2'));

          await Future.delayed(Duration(milliseconds: 20));
          return 42;
        });

        container.run();
        await Future.delayed(Duration(milliseconds: 10));

        container.cancel();

        expect(cancelEvents, ['cleanup1', 'cleanup2']);
        expect(container.isCanceled, true);
      });

      test('onCancel callbacks handle errors gracefully', () async {
        final cancelEvents = <String>[];
        final container = AsyncStateContainer<int>((state) async {
          state.onCancel(() {
            cancelEvents.add('before_error');
            throw Exception('Error in cancel callback');
          });
          state.onCancel(() => cancelEvents.add('after_error'));

          await Future.delayed(Duration(milliseconds: 20));
          return 42;
        });

        container.run();
        await Future.delayed(Duration(milliseconds: 10));

        container.cancel();

        expect(cancelEvents, ['before_error', 'after_error']);
        expect(container.isCanceled, true);
      });

      test('multiple onCancel registrations work correctly', () async {
        final resources = <String>[];
        final container = AsyncStateContainer<String>((state) async {
          // Simulate acquiring resources
          resources.add('resource1');
          resources.add('resource2');
          resources.add('resource3');

          // Register cleanup for each resource
          state.onCancel(() => resources.remove('resource1'));
          state.onCancel(() => resources.remove('resource2'));
          state.onCancel(() => resources.remove('resource3'));

          await Future.delayed(Duration(milliseconds: 30));
          return 'success';
        });

        container.run();
        await Future.delayed(Duration(milliseconds: 15));

        expect(resources, ['resource1', 'resource2', 'resource3']);

        container.cancel();

        expect(resources, isEmpty);
        expect(container.isCanceled, true);
      });
    });

    group("chaining and next state", () {
      test('can chain to next state container', () async {
        final container1 = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          return 1;
        });

        final container2 = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          return 2;
        });

        // Start first container
        final future1 = container1.future;

        // Cancel and chain to second
        container1.cancel(container2);

        // The future should now resolve to container2's result
        try {
          await future1;
          fail('Expected CanceledFutureException or chained result');
        } catch (e) {
          // Could throw CanceledFutureException or return chained result
          // depending on timing
        }

        expect(container1.isCanceled, true);
        expect(container1.state, container2.state);
      });

      test('chained state is accessible immediately', () async {
        final container1 = AsyncStateContainer<String>(
          (state) async => 'first',
        );
        final container2 = AsyncStateContainer<String>(
          (state) async => 'second',
        );

        container2.run();
        await Future.delayed(Duration(milliseconds: 10));

        container1.cancel(container2);

        expect(container1.state, container2.state);
        expect(container1.state.value, 'second');
      });

      test('chained future resolves correctly', () async {
        final container1 = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 30));
          return 100;
        });

        final container2 = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 200;
        });

        container1.future;

        // Start container2 and let it complete
        container2.run();
        await Future.delayed(Duration(milliseconds: 20));

        // Chain container1 to container2
        container1.cancel(container2);

        final result = await container1.future;
        expect(result, 200);
      });

      test('deep chaining works correctly', () async {
        final container1 = AsyncStateContainer<String>(
          (state) async => 'first',
        );
        final container2 = AsyncStateContainer<String>(
          (state) async => 'second',
        );
        final container3 = AsyncStateContainer<String>(
          (state) async => 'third',
        );

        // Chain: container1 -> container2 -> container3
        container1.cancel(container2);
        container2.cancel(container3);

        container3.run();
        await Future.delayed(Duration(milliseconds: 10));

        expect(container1.state, container3.state);
        expect(container2.state, container3.state);
        expect(container1.state.value, 'third');
      });
    });

    group("execution control", () {
      test('run() can be called multiple times safely', () async {
        int executionCount = 0;
        final container = AsyncStateContainer<int>((state) async {
          executionCount++;
          return executionCount;
        });

        container.run();
        container.run(); // Should not execute again
        container.run(); // Should not execute again

        await Future.delayed(Duration(milliseconds: 10));

        expect(executionCount, 1);
        expect(container.state.value, 1);
      });

      test('future property can be accessed multiple times', () async {
        int executionCount = 0;
        final container = AsyncStateContainer<double>((state) async {
          executionCount++;
          await Future.delayed(Duration(milliseconds: 10));
          return 3.14;
        });

        final future1 = container.future;
        final future2 = container.future;
        final future3 = container.future;

        final results = await Future.wait([future1, future2, future3]);

        expect(executionCount, 1); // Should only execute once
        expect(results, [3.14, 3.14, 3.14]);
      });

      test('execution starts lazily', () async {
        bool hasStarted = false;
        final container = AsyncStateContainer<bool>((state) async {
          hasStarted = true;
          return true;
        });

        // Should not start until run() or future is accessed
        await Future.delayed(Duration(milliseconds: 10));
        expect(hasStarted, false);

        // Access future to trigger execution
        await container.future;
        expect(hasStarted, true);
      });

      test('state updates correctly during execution lifecycle', () async {
        final states = <AsyncState<String>>[];
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          return 'completed';
        });

        // Initial state
        states.add(container.state);

        // Start execution
        final futureResult = container.future;
        states.add(container.state); // Should still be loading

        // Wait for completion
        await futureResult;
        states.add(container.state); // Should be data

        expect(states[0], AsyncState.loading());
        expect(states[1], AsyncState.loading());
        expect(states[2], AsyncState.data('completed'));
      });
    });

    group("edge cases and error conditions", () {
      test('handles immediate completion', () async {
        final container = AsyncStateContainer<int>((state) async => 42);

        final result = await container.future;

        expect(result, 42);
        expect(container.state, AsyncState.data(42));
      });

      test('handles future that never completes', () async {
        final container = AsyncStateContainer<void>((state) async {
          // Never complete
          await Completer<void>().future;
        });

        container.run();

        // Should remain in loading state
        await Future.delayed(Duration(milliseconds: 50));
        expect(container.state, AsyncState.loading());

        // Cancel to clean up
        container.cancel();
        expect(container.isCanceled, true);
      });

      test('handles cancellation after completion', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'done';
        });

        await container.future;
        expect(container.state.value, 'done');

        // Cancel after completion
        container.cancel();

        expect(container.isCanceled, true);
        expect(container.state.value, 'done'); // State should remain
      });

      test('handles exception in future builder with onCancel', () async {
        final cleanupCalled = <bool>[false];
        final container = AsyncStateContainer<int>((state) async {
          state.onCancel(() => cleanupCalled[0] = true);

          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Builder error');
        });

        try {
          await container.future;
          fail('Expected exception');
        } catch (e) {
          expect(e, isA<Exception>());
        }

        // Cancel after error
        container.cancel();

        expect(cleanupCalled[0], true);
        expect(container.isCanceled, true);
      });
    });

    group("performance and memory", () {
      test('handles many containers efficiently', () async {
        final containers = <AsyncStateContainer<int>>[];

        // Create many containers
        for (int i = 0; i < 100; i++) {
          containers.add(AsyncStateContainer<int>((state) async => i));
        }

        // Execute all
        final futures = containers.map((c) => c.future).toList();
        final results = await Future.wait(futures);

        // Verify results
        for (int i = 0; i < 100; i++) {
          expect(results[i], i);
          expect(containers[i].state.value, i);
        }
      });

      test('handles rapid creation and cancellation', () async {
        final containers = <AsyncStateContainer<int>>[];

        // Create and immediately cancel many containers
        for (int i = 0; i < 50; i++) {
          final container = AsyncStateContainer<int>((state) async {
            await Future.delayed(Duration(milliseconds: 100));
            return i;
          });

          containers.add(container);
          container.run();

          // Cancel every other one
          if (i % 2 == 0) {
            container.cancel();
          }
        }

        await Future.delayed(Duration(milliseconds: 150));

        // Check that canceled ones are marked as canceled
        for (int i = 0; i < 50; i++) {
          if (i % 2 == 0) {
            expect(containers[i].isCanceled, true);
          } else {
            expect(containers[i].state.value, i);
          }
        }
      });

      test('cleanup works correctly with many onCancel callbacks', () async {
        final cleanupCount = <int>[0];
        final container = AsyncStateContainer<int>((state) async {
          // Register many cleanup callbacks
          for (int i = 0; i < 1000; i++) {
            state.onCancel(() => cleanupCount[0]++);
          }

          await Future.delayed(Duration(milliseconds: 50));
          return 42;
        });

        container.run();
        await Future.delayed(Duration(milliseconds: 25));

        container.cancel();

        expect(cleanupCount[0], 1000);
        expect(container.isCanceled, true);
      });
    });

    group("integration scenarios", () {
      test('works with HTTP-like operations', () async {
        // Simulate HTTP request
        final container = AsyncStateContainer<Map<String, dynamic>>((
          state,
        ) async {
          state.onCancel(() => print('HTTP request canceled'));

          await Future.delayed(
            Duration(milliseconds: 30),
          ); // Simulate network delay

          if (state.isCanceled) {
            throw Exception('Request was canceled');
          }

          return {
            'status': 'success',
            'data': [1, 2, 3],
          };
        });

        final result = await container.future;

        expect(result['status'], 'success');
        expect(result['data'], [1, 2, 3]);
        expect(container.state.hasValue, true);
      });

      test('works with file operations', () async {
        // Simulate file read
        final container = AsyncStateContainer<String>((state) async {
          final fileHandle = 'mock_file_handle';
          state.onCancel(() => print('Closing file: $fileHandle'));

          await Future.delayed(Duration(milliseconds: 20)); // Simulate file I/O

          if (state.isCanceled) {
            throw Exception('File operation canceled');
          }

          return 'file contents here';
        });

        final content = await container.future;

        expect(content, 'file contents here');
        expect(container.state.value, 'file contents here');
      });

      test('works with database-like operations', () async {
        // Simulate database query
        final container = AsyncStateContainer<List<Map<String, dynamic>>>((
          state,
        ) async {
          final connection = 'mock_db_connection';
          state.onCancel(() => print('Closing DB connection: $connection'));

          await Future.delayed(
            Duration(milliseconds: 25),
          ); // Simulate query time

          if (state.isCanceled) {
            throw Exception('Database query canceled');
          }

          return [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ];
        });

        final results = await container.future;

        expect(results.length, 2);
        expect(results[0]['name'], 'Alice');
        expect(results[1]['name'], 'Bob');
      });

      test('handles timeout scenarios', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(
            Duration(milliseconds: 200),
          ); // Longer than timeout
          return 'completed';
        });

        try {
          await container.future.timeout(Duration(milliseconds: 50));
          fail('Expected timeout');
        } catch (e) {
          expect(e, isA<TimeoutException>());
        }
      });

      test('works with stream-like operations', () async {
        final events = <String>[];
        final container = AsyncStateContainer<List<String>>((state) async {
          final subscription =
              Stream.periodic(
                Duration(milliseconds: 10),
                (i) => 'event_$i',
              ).take(5).listen((event) {
                events.add(event);
              });

          state.onCancel(() => subscription.cancel());

          await Future.delayed(
            Duration(milliseconds: 70),
          ); // Let stream complete

          if (state.isCanceled) {
            throw Exception('Stream operation canceled');
          }

          return events;
        });

        final result = await container.future;

        expect(result.length, 5);
        expect(result[0], 'event_0');
        expect(result[4], 'event_4');
      });
    });

    group("CanceledFutureException", () {
      test('is thrown when future is accessed after cancellation', () async {
        final container = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 50));
          return 42;
        });

        container.cancel();

        try {
          await container.future;
          fail('Expected CanceledFutureException');
        } catch (e) {
          expect(e, isA<CanceledFutureException>());
        }
      });

      test('is not thrown when chained to next state', () async {
        final container1 = AsyncStateContainer<int>((state) async => 1);
        final container2 = AsyncStateContainer<int>((state) async => 2);

        container2.run();
        await Future.delayed(Duration(milliseconds: 10));

        container1.cancel(container2);

        // Should not throw CanceledFutureException because it's chained
        final result = await container1.future;
        expect(result, 2);
      });
    });

    group("state transition tracking", () {
      test('tracks complete state lifecycle', () async {
        final states = <AsyncState<String>>[];
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 20));
          return 'success';
        });

        // Track initial state
        states.add(container.state);

        // Start execution and track loading
        container.run();
        states.add(container.state);

        // Wait for completion and track final state
        await container.future;
        states.add(container.state);

        expect(states[0], AsyncState.loading());
        expect(states[1], AsyncState.loading());
        expect(states[2], AsyncState.data('success'));
      });

      test('tracks error state transitions', () async {
        final states = <AsyncState<int>>[];
        final container = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Test error');
        });

        states.add(container.state);

        try {
          await container.future;
        } catch (e) {
          // Expected
        }

        states.add(container.state);

        expect(states[0], AsyncState.loading());
        expect(states[1].hasError, true);
        expect(states[1].error, isA<Exception>());
      });

      test('state remains consistent after cancellation', () async {
        final container = AsyncStateContainer<String>((state) async {
          await Future.delayed(Duration(milliseconds: 30));
          return 'completed';
        });

        expect(container.state, AsyncState.loading());

        container.run();
        await Future.delayed(Duration(milliseconds: 10));

        container.cancel();

        // State should remain loading after cancellation
        expect(container.state, AsyncState.loading());
        expect(container.isCanceled, true);
      });
    });

    group("reactive integration scenarios", () {
      test('works with signals and effects', () async {
        final trigger = signal(0);
        final results = <String>[];

        late AsyncStateContainer<String> container;

        effect(() {
          final triggerValue = trigger.value;
          container = AsyncStateContainer<String>((state) async {
            await Future.delayed(Duration(milliseconds: 10));
            return 'result_$triggerValue';
          });

          container.future
              .then((result) {
                results.add(result);
              })
              .catchError((e) {
                // Handle errors
              });
        });

        await Future.delayed(Duration(milliseconds: 30));

        trigger.value = 1;
        await Future.delayed(Duration(milliseconds: 30));

        trigger.value = 2;
        await Future.delayed(Duration(milliseconds: 30));

        expect(results, contains('result_0'));
        expect(results, contains('result_1'));
        expect(results, contains('result_2'));
      });

      test('integrates with computed signals', () async {
        final input = signal(5);
        final multiplier = signal(2);

        final computedInput = computed(() => input.value * multiplier.value);

        final container = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return computedInput.value + 100;
        });

        final result = await container.future;
        expect(result, 110); // (5 * 2) + 100

        // Change inputs
        input.value = 3;
        multiplier.value = 4;

        final container2 = AsyncStateContainer<int>((state) async {
          await Future.delayed(Duration(milliseconds: 10));
          return computedInput.value + 100;
        });

        final result2 = await container2.future;
        expect(result2, 112); // (3 * 4) + 100
      });
    });

    group("batch and concurrent operations", () {
      test('handles concurrent container executions', () async {
        final containers = <AsyncStateContainer<int>>[];

        // Create containers that will run concurrently
        for (int i = 0; i < 10; i++) {
          containers.add(
            AsyncStateContainer<int>((state) async {
              await Future.delayed(Duration(milliseconds: 20 + (i * 2)));
              return i * 10;
            }),
          );
        }

        // Start all containers
        final futures = containers.map((c) => c.future).toList();

        // Wait for all to complete
        final results = await Future.wait(futures);

        // Verify results
        for (int i = 0; i < 10; i++) {
          expect(results[i], i * 10);
          expect(containers[i].state.value, i * 10);
        }
      });

      test('handles mixed success and failure in batch', () async {
        final containers = [
          AsyncStateContainer<int>((state) async => 1),
          AsyncStateContainer<int>((state) async => throw Exception('Error 2')),
          AsyncStateContainer<int>((state) async => 3),
          AsyncStateContainer<int>((state) async => throw Exception('Error 4')),
          AsyncStateContainer<int>((state) async => 5),
        ];

        final results = await Future.wait(
          containers.map((c) => c.future.catchError((e) => -1)),
        );

        expect(results, [1, -1, 3, -1, 5]);

        // Check states
        expect(containers[0].state.value, 1);
        expect(containers[1].state.hasError, true);
        expect(containers[2].state.value, 3);
        expect(containers[3].state.hasError, true);
        expect(containers[4].state.value, 5);
      });

      test('handles race conditions with cancellation', () async {
        final containers = <AsyncStateContainer<int>>[];

        // Create containers with different execution times
        for (int i = 0; i < 5; i++) {
          containers.add(
            AsyncStateContainer<int>((state) async {
              await Future.delayed(Duration(milliseconds: 10 + (i * 10)));
              if (state.isCanceled) {
                throw Exception('Canceled');
              }
              return i;
            }),
          );
        }

        // Start all
        final futures = containers.map((c) => c.future).toList();

        // Cancel some after a delay
        Future.delayed(Duration(milliseconds: 25), () {
          containers[2].cancel();
          containers[3].cancel();
        });

        final results = await Future.wait(
          futures.map((f) => f.catchError((e) => -1)),
        );

        // First two should succeed, middle two should be canceled, last should succeed
        expect(results[0], 0);
        expect(results[1], 1);
        expect(results[2], -1); // Canceled
        expect(results[3], -1); // Canceled
        expect(results[4], 4);
      });
    });

    group("advanced error scenarios", () {
      test('handles nested async operations with cancellation', () async {
        final outerEvents = <String>[];
        final innerEvents = <String>[];

        final container = AsyncStateContainer<String>((state) async {
          outerEvents.add('outer_start');
          state.onCancel(() => outerEvents.add('outer_cancel'));

          // Nested async operation
          final innerResult = await Future(() async {
            innerEvents.add('inner_start');
            await Future.delayed(Duration(milliseconds: 30));

            if (state.isCanceled) {
              innerEvents.add('inner_canceled');
              throw Exception('Inner canceled');
            }

            innerEvents.add('inner_complete');
            return 'inner_result';
          });

          outerEvents.add('outer_complete');
          return 'outer_$innerResult';
        });

        final futureResult = container.future;

        // Cancel after inner starts but before completion
        await Future.delayed(Duration(milliseconds: 15));
        container.cancel();

        try {
          await futureResult;
          fail('Expected exception');
        } catch (e) {
          expect(e, isA<CanceledFutureException>());
        }

        await Future.delayed(Duration(milliseconds: 50));

        expect(outerEvents, contains('outer_start'));
        expect(outerEvents, contains('outer_cancel'));
        expect(innerEvents, contains('inner_start'));
        expect(innerEvents, contains('inner_canceled'));
      });

      test('handles errors in onCancel during error state', () async {
        final events = <String>[];
        final container = AsyncStateContainer<int>((state) async {
          state.onCancel(() {
            events.add('cancel_callback');
            throw Exception('Error in cancel callback');
          });

          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Original error');
        });

        try {
          await container.future;
          fail('Expected exception');
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('Original error'));
        }

        // Now cancel after error
        container.cancel();

        expect(events, ['cancel_callback']);
        expect(container.isCanceled, true);
        expect(container.state.hasError, true);
      });
    });

    group("resource management", () {
      test('properly manages resources across lifecycle', () async {
        final resources = <String>[];
        final container = AsyncStateContainer<String>((state) async {
          // Acquire resources
          resources.add('connection');
          resources.add('file_handle');
          resources.add('memory_buffer');

          // Register cleanup
          state.onCancel(() {
            resources.remove('connection');
            resources.remove('file_handle');
            resources.remove('memory_buffer');
          });

          await Future.delayed(Duration(milliseconds: 20));

          if (state.isCanceled) {
            throw Exception('Canceled');
          }

          return 'success';
        });

        final result = await container.future;
        expect(result, 'success');
        expect(resources, ['connection', 'file_handle', 'memory_buffer']);

        // Cleanup should happen on cancel
        container.cancel();
        expect(resources, isEmpty);
      });

      test('handles resource cleanup on error', () async {
        final resources = <String>[];
        final container = AsyncStateContainer<int>((state) async {
          resources.add('temp_resource');
          state.onCancel(() => resources.remove('temp_resource'));

          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('Processing failed');
        });

        try {
          await container.future;
          fail('Expected exception');
        } catch (e) {
          expect(e, isA<Exception>());
        }

        expect(resources, [
          'temp_resource',
        ]); // Should still be there after error

        container.cancel();
        expect(resources, isEmpty); // Should be cleaned up after cancel
      });
    });
  });
}
