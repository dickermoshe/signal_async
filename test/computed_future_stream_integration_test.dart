import 'dart:async';

import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';
import 'package:test/test.dart';

void main() async {
  group("ComputedFuture + ComputedStream Integration", () {
    group("basic integration", () {
      test('ComputedFuture listening to ComputedStream values', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          if (streamState.hasError) {
            throw Exception('Stream error in future: ${streamState.error}');
          }
          if (!streamState.hasValue) {
            return -1; // Loading state
          }
          return streamState.value! * 2;
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        await Future.delayed(Duration(milliseconds: 50));

        // Add data to stream
        controller.add(5);
        await Future.delayed(Duration(milliseconds: 50));

        controller.add(10);
        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, greaterThanOrEqualTo(3));
        expect(events[0], AsyncState.loading()); // Initial loading
        expect(
          events.where((e) => e.hasValue && e.value == 10).isNotEmpty,
          true,
        ); // 5 * 2
        expect(
          events.where((e) => e.hasValue && e.value == 20).isNotEmpty,
          true,
        ); // 10 * 2

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });

      test('ComputedFuture awaiting ComputedStream future', () async {
        final controller = StreamController<String>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture.nonReactive((state) async {
          // Await the stream's future directly
          final streamResult = await streamSignal.future;
          return 'processed: $streamResult';
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        // Add data to stream
        controller.add('hello');
        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1], AsyncState.data('processed: hello'));

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });

      test('ComputedFuture with initialValue from ComputedStream', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(
          () => controller.stream,
          initialValue: 42,
        );

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          return streamState.requireValue + 100;
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1], AsyncState.data(142)); // 42 + 100

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });
    });

    group("error handling", () {
      test('ComputedFuture handles ComputedStream errors', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          if (streamState.hasError) {
            return -999; // Error indicator
          }
          return streamState.requireValue * 3;
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        // First send valid data
        controller.add(7);
        await Future.delayed(Duration(milliseconds: 50));

        // Then send error
        controller.addError(Exception('Stream error'));
        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, greaterThanOrEqualTo(3));
        expect(events[0], AsyncState.loading());
        expect(
          events.where((e) => e.hasValue && e.value == 21).isNotEmpty,
          true,
        ); // 7 * 3
        expect(
          events.where((e) => e.hasValue && e.value == -999).isNotEmpty,
          true,
        ); // Error indicator

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });

      test('ComputedFuture propagates ComputedStream errors', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          // This will throw if stream has error
          return streamState.requireValue * 2;
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        // Send error to stream
        controller.addError(Exception('Original stream error'));
        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, 2);
        expect(events[0], AsyncState.loading());
        expect(events[1].hasError, true);

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });

      test(
        'ComputedFuture error recovery after ComputedStream recovers',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return streamState.requireValue * 5;
          });

          final events = [];
          effect(() {
            events.add(futureSignal.value);
          });

          // Send error first
          controller.addError(Exception('Stream error'));
          await Future.delayed(Duration(milliseconds: 50));

          // Then send valid data
          controller.add(4);
          await Future.delayed(Duration(milliseconds: 50));

          expect(events.length, greaterThanOrEqualTo(3));
          expect(events[0], AsyncState.loading());
          expect(events.where((e) => e.hasError).isNotEmpty, true);
          expect(
            events.where((e) => e.hasValue && e.value == 20).isNotEmpty,
            true,
          ); // 4 * 5

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );
    });

    group("cancellation and disposal", () {
      test(
        'ComputedFuture cancellation does not affect ComputedStream',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 30));
            if (state.isCanceled) {
              return -1;
            }
            return streamState.requireValue * 10;
          });

          final streamEvents = [];
          final futureEvents = [];

          effect(() {
            streamEvents.add(streamSignal.value);
          });

          final dispose = effect(() {
            futureEvents.add(futureSignal.value);
          });

          controller.add(3);
          await Future.delayed(Duration(milliseconds: 15));

          // Dispose future effect (should cancel future computation)
          dispose();

          await Future.delayed(Duration(milliseconds: 30));

          // Stream should still be active
          controller.add(6);
          await Future.delayed(Duration(milliseconds: 20));

          expect(streamEvents.length, greaterThanOrEqualTo(2));
          expect(
            streamEvents.where((e) => e.hasValue && e.value == 3).isNotEmpty,
            true,
          );
          expect(
            streamEvents.where((e) => e.hasValue && e.value == 6).isNotEmpty,
            true,
          );

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test(
        'ComputedStream disposal affects dependent ComputedFuture',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return streamState.requireValue * 2;
          });

          final events = [];
          effect(() {
            events.add(futureSignal.value);
          });

          controller.add(8);
          await Future.delayed(Duration(milliseconds: 50));

          // Dispose stream signal
          streamSignal.dispose();
          await Future.delayed(Duration(milliseconds: 20));

          expect(streamSignal.disposed, true);
          expect(
            events.where((e) => e.hasValue && e.value == 16).isNotEmpty,
            true,
          );

          futureSignal.dispose();
          controller.close();
        },
      );

      test('autoDispose behavior with stream dependencies', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 20));
          return streamState.requireValue + 50;
        }, autoDispose: true);

        final dispose = effect(() {
          futureSignal.value;
        });

        controller.add(25);
        await Future.delayed(Duration(milliseconds: 10));

        // Dispose effect early
        dispose();

        await Future.delayed(Duration(milliseconds: 30));

        // Future should be canceled, stream should still work
        controller.add(30);
        await Future.delayed(Duration(milliseconds: 20));

        expect(streamSignal.value.value, 30);

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });
    });

    group("reactive behavior", () {
      test('ComputedFuture recomputes on ComputedStream changes', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        int computationCount = 0;
        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          if (!streamState.hasValue) {
            return 0; // Don't increment counter for loading states
          }
          computationCount++;
          await Future.delayed(Duration(milliseconds: 10));
          return streamState.requireValue * 100;
        });

        effect(() {
          futureSignal.value;
        });

        await Future.delayed(Duration(milliseconds: 20));
        expect(computationCount, 0); // No computation yet (stream loading)

        controller.add(1);
        await Future.delayed(Duration(milliseconds: 30));
        expect(computationCount, 1);

        controller.add(2);
        await Future.delayed(Duration(milliseconds: 30));
        expect(computationCount, 2);

        controller.add(3);
        await Future.delayed(Duration(milliseconds: 30));
        expect(computationCount, 3);

        futureSignal.dispose();
        streamSignal.dispose();
        controller.close();
      });

      test(
        'rapid ComputedStream changes cancel previous ComputedFuture computations',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final events = [];
          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            final value = streamState.requireValue;
            events.add('start_$value');

            state.onCancel(() => events.add('cancel_$value'));

            await Future.delayed(Duration(milliseconds: 30));

            if (state.isCanceled) {
              events.add('was_canceled_$value');
              return -1;
            }

            events.add('complete_$value');
            return value * 10;
          });

          effect(() {
            futureSignal.value;
          });

          // Rapid stream changes
          controller.add(1);
          await Future.delayed(Duration(milliseconds: 10));

          controller.add(2);
          await Future.delayed(Duration(milliseconds: 10));

          controller.add(3);
          await Future.delayed(Duration(milliseconds: 50));

          expect(events, contains('start_1'));
          expect(events, contains('cancel_1'));
          expect(events, contains('start_2'));
          expect(events, contains('cancel_2'));
          expect(events, contains('start_3'));
          expect(events, contains('complete_3'));

          // Should not complete canceled computations
          expect(events, isNot(contains('complete_1')));
          expect(events, isNot(contains('complete_2')));

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test(
        'ComputedFuture restart while listening to ComputedStream',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          int computationCount = 0;
          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            if (!streamState.hasValue) {
              return 0; // Don't increment counter for loading states
            }
            computationCount++;
            await Future.delayed(Duration(milliseconds: 10));
            return streamState.requireValue + computationCount * 1000;
          });

          effect(() {
            futureSignal.value;
          });

          controller.add(5);
          await Future.delayed(Duration(milliseconds: 30));
          expect(computationCount, 1);
          expect(futureSignal.value.value, 1005); // 5 + 1*1000

          // Manual restart - should increment computation count
          final previousCount = computationCount;
          futureSignal.restart();
          await Future.delayed(Duration(milliseconds: 30));
          expect(computationCount, previousCount + 1);
          expect(
            futureSignal.value.value,
            (previousCount + 1) * 1000 + 5,
          ); // 5 + (count)*1000

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );
    });

    group("chaining scenarios", () {
      test(
        'ComputedStream -> ComputedFuture -> ComputedFuture chain',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          // First future: double the stream value
          final firstFuture = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return streamState.requireValue * 2;
          });

          // Second future: add 100 to first future result
          final secondFuture = ComputedFuture(firstFuture, (
            state,
            firstState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return firstState.requireValue + 100;
          });

          final events = [];
          effect(() {
            events.add(secondFuture.value);
          });

          controller.add(7);
          await Future.delayed(Duration(milliseconds: 100));

          expect(events.length, greaterThanOrEqualTo(2));
          expect(events[0], AsyncState.loading());
          expect(
            events.where((e) => e.hasValue && e.value == 114).isNotEmpty,
            true,
          ); // (7*2) + 100

          controller.add(10);
          await Future.delayed(Duration(milliseconds: 100));

          expect(
            events.where((e) => e.hasValue && e.value == 120).isNotEmpty,
            true,
          ); // (10*2) + 100

          secondFuture.dispose();
          firstFuture.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test(
        'multiple ComputedFutures listening to same ComputedStream',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final future1 = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return streamState.requireValue * 2;
          });

          final future2 = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 15));
            return streamState.requireValue * 3;
          });

          final future3 = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 5));
            return streamState.requireValue + 1000;
          });

          final events1 = [];
          final events2 = [];
          final events3 = [];

          effect(() => events1.add(future1.value));
          effect(() => events2.add(future2.value));
          effect(() => events3.add(future3.value));

          controller.add(6);
          await Future.delayed(Duration(milliseconds: 100));

          expect(
            events1.where((e) => e.hasValue && e.value == 12).isNotEmpty,
            true,
          ); // 6*2
          expect(
            events2.where((e) => e.hasValue && e.value == 18).isNotEmpty,
            true,
          ); // 6*3
          expect(
            events3.where((e) => e.hasValue && e.value == 1006).isNotEmpty,
            true,
          ); // 6+1000

          future1.dispose();
          future2.dispose();
          future3.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test('ComputedFuture depending on multiple ComputedStreams', () async {
        final controller1 = StreamController<int>();
        final controller2 = StreamController<String>();

        final stream1 = ComputedStream(() => controller1.stream);
        final stream2 = ComputedStream(() => controller2.stream);

        // Combine both streams using a computed signal
        final combined = computed(
          () => (num: stream1.value, text: stream2.value),
        );

        final futureSignal = ComputedFuture(combined, (
          state,
          combinedState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          final num = combinedState.num;
          final text = combinedState.text;

          if (!num.hasValue || !text.hasValue) {
            return 'loading';
          }

          return '${text.value}: ${num.value}';
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        // Send data to first stream
        controller1.add(42);
        await Future.delayed(Duration(milliseconds: 50));

        // Send data to second stream
        controller2.add('answer');
        await Future.delayed(Duration(milliseconds: 50));

        expect(
          events.where((e) => e.hasValue && e.value == 'answer: 42').isNotEmpty,
          true,
        );

        futureSignal.dispose();
        stream1.dispose();
        stream2.dispose();
        controller1.close();
        controller2.close();
      });
    });

    group("performance and edge cases", () {
      test(
        'high-frequency ComputedStream updates with ComputedFuture',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          int computationCount = 0;
          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            computationCount++;
            // Very fast computation
            await Future.delayed(Duration(milliseconds: 1));
            return streamState.requireValue;
          });

          effect(() {
            futureSignal.value;
          });

          // Send many rapid updates
          for (int i = 1; i <= 20; i++) {
            controller.add(i);
            await Future.delayed(Duration(milliseconds: 2));
          }

          await Future.delayed(Duration(milliseconds: 50));

          // Should handle all updates
          expect(computationCount, greaterThan(15));
          expect(futureSignal.value.value, 20);

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test(
        'ComputedFuture with slow computation and fast ComputedStream',
        () async {
          final controller = StreamController<int>();
          final streamSignal = ComputedStream(() => controller.stream);

          final completedValues = [];
          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            final value = streamState.requireValue;

            // Slow computation
            await Future.delayed(Duration(milliseconds: 50));

            if (!state.isCanceled) {
              completedValues.add(value);
            }

            return value * 100;
          });

          effect(() {
            futureSignal.value;
          });

          // Fast stream updates (should cancel previous computations)
          controller.add(1);
          await Future.delayed(Duration(milliseconds: 10));

          controller.add(2);
          await Future.delayed(Duration(milliseconds: 10));

          controller.add(3);
          await Future.delayed(
            Duration(milliseconds: 100),
          ); // Let last one complete

          // Only the last computation should complete
          expect(completedValues, [3]);
          expect(futureSignal.value.value, 300);

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test('ComputedStream closes while ComputedFuture is computing', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final futureSignal = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 30));
          return streamState.requireValue * 10;
        });

        final events = [];
        effect(() {
          events.add(futureSignal.value);
        });

        controller.add(5);
        await Future.delayed(Duration(milliseconds: 15));

        // Close stream while future is computing
        controller.close();
        streamSignal.dispose();

        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, greaterThanOrEqualTo(1));
        expect(events[0], AsyncState.loading());

        futureSignal.dispose();
      });

      test('memory cleanup with many stream-future pairs', () async {
        final controllers = <StreamController<int>>[];
        final streams = <ComputedStream<int>>[];
        final futures = <ComputedFuture<int, AsyncState<int>>>[];

        // Create many stream-future pairs
        for (int i = 0; i < 10; i++) {
          final controller = StreamController<int>();
          final stream = ComputedStream(() => controller.stream);
          final future = ComputedFuture(stream, (state, streamState) async {
            await Future.delayed(Duration(milliseconds: 5));
            return streamState.requireValue + i;
          });

          controllers.add(controller);
          streams.add(stream);
          futures.add(future);

          effect(() {
            future.value; // Start each one
          });
        }

        // Add data to all streams
        for (int i = 0; i < controllers.length; i++) {
          controllers[i].add(i * 10);
        }

        await Future.delayed(Duration(milliseconds: 50));

        // Verify all are working
        for (int i = 0; i < futures.length; i++) {
          expect(futures[i].value.hasValue, true);
          expect(futures[i].value.value, (i * 10) + i);
        }

        // Dispose all
        for (final future in futures) {
          future.dispose();
        }
        for (final stream in streams) {
          stream.dispose();
        }
        for (final controller in controllers) {
          controller.close();
        }

        await Future.delayed(Duration(milliseconds: 20));

        // Verify cleanup
        for (final future in futures) {
          expect(future.disposed, true);
        }
        for (final stream in streams) {
          expect(stream.disposed, true);
        }
      });
    });

    group("future property integration", () {
      test(
        'await ComputedFuture.future that depends on ComputedStream',
        () async {
          final controller = StreamController<String>();
          final streamSignal = ComputedStream(() => controller.stream);

          final futureSignal = ComputedFuture(streamSignal, (
            state,
            streamState,
          ) async {
            await Future.delayed(Duration(milliseconds: 10));
            return 'Processed: ${streamState.requireValue}';
          });

          effect(() {
            futureSignal.value; // Start computation
          });

          // Test awaiting future before stream has data
          final futureResult = futureSignal.future;

          controller.add('test data');

          final result = await futureResult;
          expect(result, 'Processed: test data');

          futureSignal.dispose();
          streamSignal.dispose();
          controller.close();
        },
      );

      test('chained future awaits with stream dependency', () async {
        final controller = StreamController<int>();
        final streamSignal = ComputedStream(() => controller.stream);

        final future1 = ComputedFuture(streamSignal, (
          state,
          streamState,
        ) async {
          await Future.delayed(Duration(milliseconds: 10));
          return streamState.requireValue * 2;
        });

        final future2 = ComputedFuture.nonReactive((state) async {
          final result1 = await future1.future;
          return result1 + 1000;
        });

        effect(() {
          future1.value;
          future2.value;
        });

        controller.add(25);

        final finalResult = await future2.future;
        expect(finalResult, 1050); // (25 * 2) + 1000

        future1.dispose();
        future2.dispose();
        streamSignal.dispose();
        controller.close();
      });
    });
  });
}
