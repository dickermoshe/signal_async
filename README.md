# signals_async

A reactive asynchronous signal library for Dart that extends the [signals](https://pub.dev/packages/signals) package with `ComputedFuture` and `ComputedStream` - powerful ways to handle asynchronous operations and streams reactively.

## Features

- **Reactive Async Operations**: `ComputedFuture` automatically recomputes when input signals change
- **Stream Integration**: `ComputedStream` wraps any Dart stream into a reactive signal
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
  signals_async: ^2.0.1
```

## Table of Contents

- [signals\_async](#signals_async)
  - [Features](#features)
  - [Installation](#installation)
  - [Table of Contents](#table-of-contents)
  - [ComputedFuture](#computedfuture)
    - [Basic Usage](#basic-usage)
    - [Lazy vs Eager Mode](#lazy-vs-eager-mode)
    - [Initial Values](#initial-values)
    - [Cancellation](#cancellation)
      - [Debouncing Requests](#debouncing-requests)
      - [Cancellation with HTTP Libraries](#cancellation-with-http-libraries)
    - [Chaining ComputedFutures](#chaining-computedfutures)
    - [Multiple Inputs](#multiple-inputs)
    - [Non-Reactive Mode](#non-reactive-mode)
    - [Manual Restart](#manual-restart)
  - [ComputedStream](#computedstream)
    - [Basic Usage](#basic-usage-1)
    - [Initial Values and Lazy Mode](#initial-values-and-lazy-mode)
    - [Chaining with ComputedFuture](#chaining-with-computedfuture)
  - [Common Use Cases](#common-use-cases)
    - [Debouncing Search Requests](#debouncing-search-requests)
    - [Polling Data](#polling-data)
  - [Error Handling Patterns](#error-handling-patterns)
    - [Try-Catch in ComputedFuture](#try-catch-in-computedfuture)
    - [Retry Logic](#retry-logic)
  - [Simple Flutter Example](#simple-flutter-example)
  - [License](#license)



## ComputedFuture

`ComputedFuture` creates a reactive asynchronous signal that automatically recomputes when input signals change.

### Basic Usage

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';

final input = signal(2);
final result = ComputedFuture(input, (state, value) async {
  // Fetch data from the API
  final response = await http.get(Uri.parse('https://api.example.com/data/$value'));
  return jsonDecode(response.body);
});

// Listen to state changes
effect(() {
  final state = result.value;
  if (state is AsyncData) {
    print('Result: ${state.value}');  // Prints the data from the API
  } else if (state is AsyncLoading) {
    print('Loading...');
  } else if (state is AsyncError) {
    print('Error: ${state.error}');
  }
});

input.value = 3;  // Triggers new request
```



### Lazy vs Eager Mode

By default, `ComputedFuture` is **lazy** - it won't start the async operation until the `value` or `future` is accessed (typically in an `effect`).

```dart
// Lazy (default) - starts when first accessed
final lazyResult = ComputedFuture(input, (state, value) async {
  print('Starting lazy computation for: $value');
  final response = await http.get(Uri.parse('https://api.example.com/data/$value'));
  return jsonDecode(response.body);
});

// Eager - starts immediately
final eagerResult = ComputedFuture(input, (state, value) async {
  print('Starting eager computation for: $value');
  final response = await http.get(Uri.parse('https://api.example.com/data/$value'));
  return jsonDecode(response.body);
}, lazy: false);

// The lazy one won't start until this effect runs
effect(() {
  print('Lazy state: ${lazyResult.value}');
});
```

### Initial Values

You can provide an initial value to avoid showing a loading state initially:

```dart
final result = ComputedFuture(
  input,
  (state, value) async {
    final response = await http.get(Uri.parse('https://api.example.com/data/$value'));
    return jsonDecode(response.body);
  },
  initialValue: {'placeholder': 'data'}, // Show this initially
);

effect(() {
  final state = result.value;
  // Will show initial data immediately, then real data
  if (state is AsyncData) {
    print('Data: ${state.value}');
  }
});
```

### Cancellation

Futures are canceled when one of the following happens:
- The input signal changes
- The `ComputedFuture` is disposed (either automatically when the effect is disposed or manually when `dispose` is called)
- The `ComputedFuture` is restarted

> [!IMPORTANT]
> This does not actually kill the Dart Future - Dart cannot cancel Futures.   
> Instead, the library provides a cancellation state that you can check and respond to in your async operations.

#### Debouncing Requests

Use `state.isCanceled` to check if the operation should be aborted:

```dart
final searchQuery = signal('');
final searchResults = ComputedFuture(searchQuery, (state, query) async {
  // Wait for the user to stop typing
  await Future.delayed(Duration(milliseconds: 100));
  
  // If the user has changed the query during the delay, cancel the request
  // by throwing an exception.
  if (state.isCanceled) {
    throw Exception('Request canceled');
  }
  
  // Expensive API call
  final response = await http.get(Uri.parse('https://api.example.com/search?q=$query'));
  return jsonDecode(response.body);
});

// Rapid typing will cancel previous searches
searchQuery.value = 'a';
await Future.delayed(Duration(milliseconds: 20));
searchQuery.value = 'ap';  // Aborts the request for 'a', and starts the request for 'ap'
await Future.delayed(Duration(milliseconds: 20));
searchQuery.value = 'app'; // Aborts the request for 'ap', and starts the request for 'app'
```

#### Cancellation with HTTP Libraries

You can also use `state.onCancel()` to register cleanup callbacks that run when the operation is canceled.

This is particularly useful with HTTP libraries like `dio` that support cancellation tokens:

```dart
import 'package:dio/dio.dart';

final dio = Dio();
final searchQuery = signal('');
final searchResults = ComputedFuture(searchQuery, (state, query) async {
  final cancelToken = CancelToken();
  
  // Cancel the HTTP request when the ComputedFuture is canceled
  state.onCancel(() {
    cancelToken.cancel('Operation canceled due to new request');
  });
  
  return dio.get(
    'https://api.example.com/search?q=$query',
    cancelToken: cancelToken,
  );
});
```


### Chaining ComputedFutures

You can chain `ComputedFuture`s together to create a pipeline of asynchronous operations.

```dart
final userId = signal(1);
final userProfile = ComputedFuture(userId, (state, id) async {
  final response = await http.get(Uri.parse('https://api.example.com/users/$id'));
  return jsonDecode(response.body);
});

final userPosts = ComputedFuture(userProfile, (state, _) async {
  final profile = await userProfile.future;
  final response = await http.get(Uri.parse('https://api.example.com/posts?author=${profile['username']}'));
  return jsonDecode(response.body);
});
```

### Multiple Inputs

If you'd like to use multiple inputs, use a `computed` signal to combine them into a single input.


```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';

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

### Non-Reactive Mode

Use `ComputedFuture.nonReactive` for one-off async tasks that don't depend on signals but can be manually restarted:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

final dataLoader = ComputedFuture.nonReactive((state) async {
  print('Loading data...');
  final response = await http.get(Uri.parse('https://api.example.com/data'));
  return jsonDecode(response.body);
});

// Listen to the result
effect(() {
  final state = dataLoader.value;
  if (state is AsyncData) {
    print('Loaded: ${state.value}');
  } else if (state is AsyncError) {
    print('Failed: ${state.error}');
  }
});
```

### Manual Restart

You can manually restart any `ComputedFuture` by calling `restart()`. This cancels the current operation and starts a new one.


## ComputedStream

`ComputedStream` wraps any Dart Stream into a reactive signal, automatically managing subscriptions and exposing the latest stream value as an `AsyncState`.

### Basic Usage

```dart
import 'dart:async';
import 'package:signals_async/signals_async.dart';
import 'package:signals/signals.dart';

final controller = StreamController<int>();
final streamSignal = ComputedStream(() => controller.stream);

effect(() {
  final state = streamSignal.value;
  if (state is AsyncData) {
    print('Stream value: ${state.value}');
  } else if (state is AsyncError) {
    print('Stream error: ${state.error}');
  } else if (state is AsyncLoading) {
    print('Waiting for first stream value...');
  }
});

controller.add(42);  // Prints: Stream value: 42
controller.add(100); // Prints: Stream value: 100
controller.close();
```


### Initial Values and Lazy Mode

```dart
// With initial value - shows immediately before first stream event
final streamWithInitial = ComputedStream(
  () => Stream.periodic(Duration(seconds: 1), (i) => i),
  initialValue: -1, // Shows this first
);

// Eager mode - subscribes immediately
final eagerStream = ComputedStream(
  () => Stream.periodic(Duration(seconds: 1), (i) => i),
  lazy: false, // Starts immediately
);
```
### Chaining with ComputedFuture

Combine streams with futures for complex reactive pipelines:

```dart
// Stream of user IDs
final userIdStream = ComputedStream(() => Stream.periodic(
  Duration(seconds: 2), 
  (i) => i + 1,
));

// Fetch user data whenever the stream emits
final userData = ComputedFuture(userIdStream, (state, _) async {
  final userId = await userIdStream.future; // Get latest stream value
  final response = await http.get(Uri.parse('https://api.example.com/users/$userId'));
  return jsonDecode(response.body);
});

effect(() {
  final streamState = userIdStream.value;
  final futureState = userData.value;
  
  print('Stream: $streamState');
  print('User data: $futureState');
});
```

## Common Use Cases

### Debouncing Search Requests

Perfect for search-as-you-type functionality:

```dart
final searchQuery = signal('');
final searchResults = ComputedFuture(searchQuery, (state, query) async {
  if (query.isEmpty) return <String>[];
  
  // Add a small delay to debounce rapid typing
  await Future.delayed(Duration(milliseconds: 300));
  
  // Check if canceled (user typed more)
  if (state.isCanceled) {
    throw Exception('Search canceled');
  }
  
  final response = await http.get(
    Uri.parse('https://api.example.com/search?q=${Uri.encodeComponent(query)}')
  );
  
  return (jsonDecode(response.body)['results'] as List)
      .cast<String>();
});

// Usage in UI
effect(() {
  final state = searchResults.value;
  switch (state) {
    case AsyncLoading():
      print('Searching...');
    case AsyncData(value: final results):
      print('Found ${results.length} results');
    case AsyncError():
      print('Search failed');
  }
});

// Rapid typing automatically cancels previous searches
searchQuery.value = 'fl';
searchQuery.value = 'flu';  
searchQuery.value = 'flutter'; // Only this search will complete
```

### Polling Data

Automatically refresh data at intervals:

```dart
final refreshTrigger = signal(0);

// Refresh every 30 seconds
Timer.periodic(Duration(seconds: 30), (_) {
  refreshTrigger.value++;
});

final liveData = ComputedFuture(refreshTrigger, (state, _) async {
  final response = await http.get(Uri.parse('https://api.example.com/live-data'));
  return jsonDecode(response.body);
});

// Manual refresh button
void refresh() {
  refreshTrigger.value++;
}
```

## Error Handling Patterns

### Try-Catch in ComputedFuture

```dart
final apiCall = ComputedFuture(userId, (state, id) async {
  try {
    final response = await http.get(Uri.parse('https://api.example.com/users/$id'));
    
    if (response.statusCode != 200) {
      throw HttpException('Failed to load user: ${response.statusCode}');
    }
    
    return jsonDecode(response.body);
  } catch (e) {
    // Log the error
    print('API call failed: $e');
    
    // Re-throw to let AsyncState handle it
    rethrow;
  }
});

```

### Retry Logic

```dart
final retryableCall = ComputedFuture.nonReactive((state) async {
  int attempts = 0;
  const maxAttempts = 3;
  
  while (attempts < maxAttempts) {
    try {
      if (state.isCanceled) throw Exception('Canceled');
      
      final response = await http.get(Uri.parse('https://api.example.com/data'));
      return jsonDecode(response.body);
    } catch (e) {
      attempts++;
      if (attempts >= maxAttempts) rethrow;
      
      print('Attempt $attempts failed, retrying...');
      await Future.delayed(Duration(seconds: attempts)); // Exponential backoff
    }
  }
  
  throw Exception('All attempts failed');
});
```

## Simple Flutter Example

Here's a basic example showing how to use `ComputedFuture` in a Flutter widget:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals.dart';
import 'package:signals_async/signals_async.dart';

class UserProfileWidget extends StatefulWidget {
  @override
  State<UserProfileWidget> createState() => _UserProfileWidgetState();
}

class _UserProfileWidgetState extends State<UserProfileWidget> {
  late final Signal<int> userId;
  late final ComputedFuture<Map<String, dynamic>, int> userProfile;

  @override
  void initState() {
    super.initState();
    
    // Create a reactive signal for user ID
    userId = signal(1);
    
    // Create a ComputedFuture that fetches user data when userId changes
    userProfile = ComputedFuture(userId, (state, id) async {
      // Real API call (replace with your endpoint)
      final response = await http.get(
        Uri.parse('https://jsonplaceholder.typicode.com/users/$id'),
      );
      
      // Check if the request was canceled
      if (state.isCanceled) {
        throw Exception('Request canceled');
      }
      
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // User ID selector
        Row(
          children: [
            Text('User ID: '),
            ...List.generate(3, (index) {
              final id = index + 1;
              return Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Watch((context) => ElevatedButton(
                  onPressed: () => userId.value = id,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: userId.value == id ? Colors.blue : null,
                  ),
                  child: Text('$id'),
                )),
              );
            }),
          ],
        ),
        
        SizedBox(height: 16),
        
        // User profile display
        Watch((context) {
          final state = userProfile.value;
          
          return switch (state) {
            AsyncLoading() => CircularProgressIndicator(),
            AsyncError(:final error) => Text('Error: $error'),
            AsyncData(:final value) => Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value['name'] ?? 'Unknown',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text('Email: ${value['email'] ?? 'N/A'}'),
                    Text('Phone: ${value['phone'] ?? 'N/A'}'),
                  ],
                ),
              ),
            ),
          };
        }),
      ],
    );
  }
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.