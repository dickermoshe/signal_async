# signals_async

A reactive asynchronous signal library for Dart that extends the [signals](https://pub.dev/packages/signals) package with `ComputedFuture` - a powerful way to handle asynchronous operations reactively.

## Features

- **Reactive Async Operations**: `ComputedFuture` automatically recomputes when input signals change
- **Cancellation Support**: Robust cancellation during restarts or disposal, preserving awaiters
- **Lazy Evaluation**: Defaults to lazy loading (starts on first access) with eager option available
- **Initial Values**: Optional initial values to avoid loading flickers
- **Auto-Disposal**: Automatic cleanup when effects are disposed
- **State Management**: Exposes `AsyncState<T>` for UI state and raw `Future<T>` for direct awaiting
- **Non-Reactive Mode**: Support for one-off async tasks with manual restart capability

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  signals_async: ^1.0.0
```

## Usage

### Basic Reactive Computation

```dart
import 'package:signals_async/signals_async.dart';

final input = signal(2);
final result = ComputedFuture(input, (state, value) async {
  // Use 'state' for cancellation checks
  await Future.delayed(Duration(seconds: 1));
  if (state.isCanceled){
    throw Exception('Cancelled');
  }
  return value * 2;
});

// Listen to state changes
effect(() {
  final state = result.value;
  if (state is AsyncData<int>) {
    print('Result: ${state.value}');  // Prints 4 initially
  }
});

input.value = 3;  // Triggers recompute, prints 6
```

### Multiple Inputs with Records

```dart
final userId = signal(1);
final category = signal('electronics');

// Combine multiple inputs into a record
final searchParams = computed(() => (userId: userId.value, category: category.value));

final searchResults = ComputedFuture(searchParams, (state, params) async {
  final response = await http.get(Uri.parse(
    'https://api.example.com/search?user=${params.userId}&category=${params.category}'
  ));
  return jsonDecode(response.body);
});

// Changing either input triggers a new search
userId.value = 2;           // Triggers recompute
category.value = 'books';   // Triggers recompute
```

### Chaining ComputedFutures

```dart
final userId = signal(1);

// First future: fetch user profile
final userProfile = ComputedFuture(userId, (state, id) async {
  final response = await http.get(Uri.parse('https://api.example.com/users/$id'));
  return jsonDecode(response.body);
});

// Second future depends on the first
final userPosts = ComputedFuture(userProfile, (state, _) async {
  final profile = await userProfile.future;
  final response = await http.get(Uri.parse(
    'https://api.example.com/posts?author=${profile['username']}'
  ));
  return jsonDecode(response.body);
});

// When userId changes, both futures recompute in sequence
userId.value = 2;
```

### Non-Reactive Mode

```dart
final fetchData = ComputedFuture.nonReactive((state) async {
  final response = await http.get(Uri.parse('https://api.example.com/data'));
  state.onCancel(() => controller?.dispose());  // Cleanup on cancel
  return jsonDecode(response.body);
});

effect(() => print(fetchData.value));  // Triggers initial fetch

fetchData.restart();  // Manual refresh
```

### Cancellation and Cleanup

```dart
final apiCall = ComputedFuture(input, (state, value) async {
  final cancelToken = CancelToken();
  
  // Register cleanup callback
  state.onCancel(() => cancelToken.cancel());
  
  final response = await dio.get('/api/data', cancelToken: cancelToken);
  return response.data;
  
});
```

## API Reference

### ComputedFuture

The main class for reactive asynchronous computations.

#### Constructors

- `ComputedFuture(input, futureBuilder, {...})` - Creates a reactive future
- `ComputedFuture.nonReactive(futureBuilder, {...})` - Creates a non-reactive future

#### Properties

- `value` - Returns the current `AsyncState<T>`
- `future` - Returns the raw `Future<T>`

#### Methods

- `restart()` - Manually restarts the computation

### FutureState

Manages the state of an asynchronous operation with cancellation support.

#### Properties

- `isCanceled` - Returns true if the operation was canceled

#### Methods

- `onCancel(callback)` - Registers a cleanup callback for when the operation is canceled

## License

This project is licensed under the MIT License - see the LICENSE file for details.