import 'dart:async';

import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';
import 'package:test/test.dart';

void main() async {
  group("ComputedStream", () {
    group("basic functionality", () {
      test('creates and subscribes to stream', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        expect(computed.peek(), AsyncState.loading());
        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Add some data to the stream
        controller.add(1);
        await Future.delayed(Duration(milliseconds: 10));

        controller.add(2);
        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [
          AsyncState.loading(),
          AsyncState.data(1),
          AsyncState.data(2),
        ]);

        controller.close();
      });

      test('supports initialValue parameter', () async {
        final controller = StreamController<String>();
        final computed = ComputedStream(
          () => controller.stream,
          initialValue: 'initial',
        );

        expect(computed.peek(), AsyncState.data('initial'));

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        controller.add('first');
        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [AsyncState.data('initial'), AsyncState.data('first')]);

        controller.close();
      });

      test('supports debugLabel parameter', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(
          () => controller.stream,
          debugLabel: 'test-stream',
        );

        expect(computed.debugLabel, 'test-stream');
        computed.dispose(); // Clean up
        controller.close();
      });
    });

    group("lazy behavior", () {
      test('lazy=true (default) - stream starts when accessed', () async {
        bool streamCreated = false;
        final controller = StreamController<int>();

        final computed = ComputedStream(() {
          streamCreated = true;
          return controller.stream;
        });

        // Should not create stream immediately
        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreated, false);
        expect(computed.peek(), AsyncState.loading());

        // Should create when accessed
        effect(() {
          computed.value;
        });

        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreated, true);

        controller.close();
      });

      test('lazy=false - stream starts immediately', () async {
        bool streamCreated = false;
        final controller = StreamController<int>();

        final computed = ComputedStream(() {
          streamCreated = true;
          return controller.stream;
        }, lazy: false);

        // Should create stream immediately
        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreated, true);
        computed.dispose();

        controller.close();
      });
    });

    group("autoDispose behavior", () {
      test(
        'autoDispose=true cancels subscription when effect disposed',
        () async {
          final controller = StreamController<int>();

          final computed = ComputedStream(
            () => controller.stream,
            autoDispose: true,
          );

          final dispose = effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 10));

          // Dispose effect
          dispose();
          computed.dispose();

          await Future.delayed(Duration(milliseconds: 10));
          expect(computed.disposed, true);

          controller.close();
        },
      );

      test(
        'autoDispose=false keeps subscription after effect disposed',
        () async {
          final controller = StreamController<int>();
          final computed = ComputedStream(
            () => controller.stream,
            autoDispose: false,
          );

          final dispose = effect(() {
            computed.value;
          });

          await Future.delayed(Duration(milliseconds: 10));

          // Dispose effect but not the computed stream
          dispose();

          // Stream should still be active
          controller.add(42);
          await Future.delayed(Duration(milliseconds: 10));
          expect(computed.value.value, 42);

          computed.dispose();
          controller.close();
        },
      );
    });

    group("error handling", () {
      test('handles stream errors', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Add error to stream
        controller.addError(Exception('Stream error'));
        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);
        expect(events[1].error, isA<Exception>());

        controller.close();
      });

      test('recovers from errors with new data', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Add error then data
        controller.addError(Exception('Stream error'));
        await Future.delayed(Duration(milliseconds: 10));

        controller.add(42);
        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 3);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);
        expect(events[2], AsyncState.data(42));

        controller.close();
      });

      test('handles multiple consecutive errors', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Add multiple errors
        controller.addError(Exception('Error 1'));
        await Future.delayed(Duration(milliseconds: 10));

        controller.addError(Exception('Error 2'));
        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 3);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);
        expect(events[2].hasError, true);
        expect(events[1].error.toString(), contains('Error 1'));
        expect(events[2].error.toString(), contains('Error 2'));

        controller.close();
      });
    });

    group("future property", () {
      test('future property returns stream data', () async {
        final controller = StreamController<String>();
        final computed = ComputedStream(() => controller.stream);

        // Access future before adding data
        final futureResult = computed.future;

        effect(() {
          computed.value; // Start stream
        });

        controller.add('stream result');

        final result = await futureResult;
        expect(result, 'stream result');

        controller.close();
      });

      test('future property with initialValue returns immediately', () async {
        final controller = StreamController<String>();
        final computed = ComputedStream(
          () => controller.stream,
          initialValue: 'initial',
        );

        final result = await computed.future;
        expect(result, 'initial');

        controller.close();
      });

      test('future property throws on stream error', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        effect(() {
          computed.value; // Start stream
        });

        final futureResult = computed.future;
        controller.addError(Exception('Stream error'));

        try {
          await futureResult;
          fail('Expected exception to be thrown');
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('Stream error'));
        }

        controller.close();
      });

      test('future property updates with new stream values', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        effect(() {
          computed.value; // Start stream
        });

        // First value
        controller.add(1);
        final firstResult = await computed.future;
        expect(firstResult, 1);

        // Wait a bit for the stream to be ready for next value
        await Future.delayed(Duration(milliseconds: 10));

        // Second value - should get new future
        controller.add(2);
        await Future.delayed(Duration(milliseconds: 10));
        final secondResult = await computed.future;
        expect(secondResult, 2);

        computed.dispose();
        controller.close();
      });
    });

    group("stream lifecycle", () {
      test('disposes subscription on dispose', () async {
        final controller = StreamController<int>();

        final computed = ComputedStream(() => controller.stream);

        effect(() {
          computed.value; // Start stream
        });

        await Future.delayed(Duration(milliseconds: 10));
        computed.dispose();

        await Future.delayed(Duration(milliseconds: 10));
        expect(computed.disposed, true);

        controller.close();
      });

      test('stream future can be awaited after disposal', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        effect(() {
          computed.value; // Start stream
        });
        final futureResult = computed.future;
        controller.add(42);

        await Future.delayed(Duration(milliseconds: 10));
        computed.dispose();
        expect(await futureResult, 42);
      });

      test(
        'disposing stream with initial value does not cause future timeout',
        () async {
          final controller = StreamController<int>();
          final computed = ComputedStream(
            () => controller.stream,
            initialValue: 42,
          );

          effect(() {
            computed.value; // Start stream
          });

          // Get the future before disposing - should use initial value
          final futureResult = computed.future;

          // Dispose immediately without adding stream data
          computed.dispose();

          // The future should complete with initial value and not timeout
          final result = await futureResult.timeout(
            Duration(milliseconds: 100),
            onTimeout: () => -1,
          );

          expect(result, 42); // Should get initial value
          expect(computed.disposed, true);

          controller.close();
        },
      );
      test(
        'disposing stream without any data does not cause future timeout and throws a StateError',
        () async {
          final controller = StreamController<int>();
          final computed = ComputedStream(() => controller.stream);

          effect(() {
            computed.value; // Start stream
          });

          final futureResult = computed.future;
          computed.dispose();
          try {
            await futureResult.timeout(Duration(milliseconds: 100));
            fail('Expected exception to be thrown');
          } catch (e) {
            expect(e, isA<StateError>());
          }

          controller.close();
        },
      );

      test('handles stream closing gracefully', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        controller.add(42);
        await Future.delayed(Duration(milliseconds: 10));

        controller.close();
        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [AsyncState.loading(), AsyncState.data(42)]);
      });

      test('multiple access to value does not restart stream', () async {
        int streamCreateCount = 0;
        final controller = StreamController<int>();

        final computed = ComputedStream(() {
          streamCreateCount++;
          return controller.stream;
        });

        effect(() {
          computed.value; // First access
        });

        await Future.delayed(Duration(milliseconds: 10));

        effect(() {
          computed.value; // Second access
        });

        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreateCount, 1); // Should only create once

        controller.close();
      });
    });

    group("data flow", () {
      test('emits multiple values in sequence', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Emit sequence of values
        for (int i = 1; i <= 5; i++) {
          controller.add(i);
          await Future.delayed(Duration(milliseconds: 5));
        }

        expect(events, [
          AsyncState.loading(),
          AsyncState.data(1),
          AsyncState.data(2),
          AsyncState.data(3),
          AsyncState.data(4),
          AsyncState.data(5),
        ]);

        controller.close();
      });

      test('handles rapid stream emissions', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Rapid emissions
        controller.add(1);
        controller.add(2);
        controller.add(3);

        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 4); // loading + 3 data events
        expect(events[0], AsyncState.loading());
        expect(events[1], AsyncState.data(1));
        expect(events[2], AsyncState.data(2));
        expect(events[3], AsyncState.data(3));

        controller.close();
      });

      test('handles different data types', () async {
        final stringController = StreamController<String>();
        final stringComputed = ComputedStream(() => stringController.stream);

        final listController = StreamController<List<int>>();
        final listComputed = ComputedStream(() => listController.stream);

        final mapController = StreamController<Map<String, dynamic>>();
        final mapComputed = ComputedStream(() => mapController.stream);

        // Start all streams
        effect(() {
          stringComputed.value;
          listComputed.value;
          mapComputed.value;
        });

        // Test different data types
        stringController.add('hello');
        listController.add([1, 2, 3]);
        mapController.add({'key': 'value', 'number': 42});

        await Future.delayed(Duration(milliseconds: 10));

        expect(stringComputed.value.value, 'hello');
        expect(listComputed.value.value, [1, 2, 3]);
        expect(mapComputed.value.value, {'key': 'value', 'number': 42});

        stringController.close();
        listController.close();
        mapController.close();
      });
    });

    group("edge cases", () {
      test('handles null values in stream', () async {
        final controller = StreamController<String?>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        controller.add(null);
        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasValue, true);
        expect(events[1].value, null);

        computed.dispose();
        controller.close();
      });

      test('handles empty stream that closes immediately', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Close immediately without emitting data
        controller.close();
        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [AsyncState.loading()]);
      });

      test('handles stream that emits then errors', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        controller.add(42);
        await Future.delayed(Duration(milliseconds: 10));

        controller.addError(Exception('After data error'));
        await Future.delayed(Duration(milliseconds: 10));

        expect(events.length, 3);
        expect(events[0], AsyncState.loading());
        expect(events[1], AsyncState.data(42));
        expect(events[2].hasError, true);

        controller.close();
      });

      test('handles periodic stream', () async {
        int counter = 0;
        final computed = ComputedStream(() {
          return Stream.periodic(Duration(milliseconds: 20), (_) => ++counter);
        });

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 100));

        expect(
          events.length,
          greaterThan(3),
        ); // Should have loading + several data events
        expect(events[0], AsyncState.loading());
        expect(events[1], AsyncState.data(1));
        expect(events[2], AsyncState.data(2));

        computed.dispose();
      });
    });

    group("performance and memory", () {
      test('properly cleans up resources', () async {
        final controllers = <StreamController<int>>[];
        final computedStreams = <ComputedStream<int>>[];

        // Create multiple streams
        for (int i = 0; i < 10; i++) {
          final controller = StreamController<int>();
          controllers.add(controller);

          final computed = ComputedStream(() => controller.stream);
          computedStreams.add(computed);

          effect(() {
            computed.value; // Start each stream
          });
        }

        await Future.delayed(Duration(milliseconds: 10));

        // Dispose all
        for (final computed in computedStreams) {
          computed.dispose();
        }

        for (final controller in controllers) {
          controller.close();
        }

        await Future.delayed(Duration(milliseconds: 10));

        // Verify all are disposed
        for (final computed in computedStreams) {
          expect(computed.disposed, true);
        }
      });

      test('handles high-frequency stream updates', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() => controller.stream);

        int eventCount = 0;
        effect(() {
          computed.value;
          eventCount++;
        });

        // Send many rapid updates
        for (int i = 0; i < 100; i++) {
          controller.add(i);
        }

        await Future.delayed(Duration(milliseconds: 50));

        expect(eventCount, 101); // loading + 100 data events
        expect(computed.value.value, 99); // Last value

        controller.close();
      });
    });

    group("integration scenarios", () {
      test('works with broadcast streams', () async {
        final controller = StreamController<int>.broadcast();
        final computed1 = ComputedStream(() => controller.stream);
        final computed2 = ComputedStream(() => controller.stream);

        final events1 = [];
        final events2 = [];

        effect(() {
          events1.add(computed1.value);
        });

        effect(() {
          events2.add(computed2.value);
        });

        controller.add(42);
        await Future.delayed(Duration(milliseconds: 10));

        expect(events1, [AsyncState.loading(), AsyncState.data(42)]);
        expect(events2, [AsyncState.loading(), AsyncState.data(42)]);

        controller.close();
      });

      test('works with transformed streams', () async {
        final controller = StreamController<int>();
        final computed = ComputedStream(() {
          return controller.stream
              .where((value) => value.isEven)
              .map((value) => value * 2);
        });

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        // Send mix of even and odd numbers
        controller.add(1); // filtered out
        controller.add(2); // becomes 4
        controller.add(3); // filtered out
        controller.add(4); // becomes 8

        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [
          AsyncState.loading(),
          AsyncState.data(4),
          AsyncState.data(8),
        ]);

        controller.close();
      });

      test('works with async* generated streams', () async {
        Stream<int> generateNumbers() async* {
          for (int i = 1; i <= 3; i++) {
            await Future.delayed(Duration(milliseconds: 10));
            yield i;
          }
        }

        final computed = ComputedStream(() => generateNumbers());

        final events = [];
        effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 50));

        expect(events, [
          AsyncState.loading(),
          AsyncState.data(1),
          AsyncState.data(2),
          AsyncState.data(3),
        ]);
      });

      test('chained with other signals', () async {
        final controller = StreamController<int>();
        final multiplier = signal(2);

        final streamComputed = ComputedStream(() => controller.stream);
        final chainedComputed = computed(() {
          final streamValue = streamComputed.value;
          if (streamValue.hasValue) {
            return streamValue.value! * multiplier.value;
          }
          return 0;
        });

        final events = [];
        effect(() {
          events.add(chainedComputed.value);
        });

        controller.add(5);
        await Future.delayed(Duration(milliseconds: 10));

        multiplier.value = 3;
        await Future.delayed(Duration(milliseconds: 10));

        expect(events, [0, 10, 15]); // 0 (loading), 5*2, 5*3

        controller.close();
      });
    });

    group("restart functionality", () {
      test('stream subscription is created only once per instance', () async {
        int streamCreateCount = 0;
        final controller = StreamController<int>();

        final computed = ComputedStream(() {
          streamCreateCount++;
          return controller.stream;
        });

        final events = [];
        final dispose = effect(() {
          events.add(computed.value);
        });

        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreateCount, 1);

        // Multiple accesses shouldn't recreate the stream
        computed.value;
        computed.value;

        await Future.delayed(Duration(milliseconds: 10));
        expect(streamCreateCount, 1); // Still only 1

        dispose();
        computed.dispose();
        controller.close();
      });
    });
  });
}
