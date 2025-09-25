/// An exception thrown when trying to access an async signal that is in an error state.
///
/// This is typically thrown when a [ComputedAsync] encounters an error during computation
/// or when awaiting the [future] property of a failed async signal.
///
/// ```dart
/// try {
///   final result = await myAsyncSignal.future;
/// } on AsyncSignalException catch (e) {
///   print('Error: ${e.exception}');
/// }
/// ```
final class AsyncSignalException implements Exception {
  AsyncSignalException._(this.exception, this.stackTrace);

  /// The original exception that caused the async signal to fail.
  final Object exception;

  /// The stack trace of the original exception.
  final StackTrace stackTrace;

  /// Returns a string representation of this exception.
  @override
  String toString() {
    if (exception case final AsyncSignalException exception) {
      return '''
$exception

And rethrown at:
$stackTrace''';
    }

    return '''
AsyncSignalException: Tried to use a AsyncSignal that is in error state.

A AsyncSignal threw the following exception:
$exception

The stack trace of the exception:
$stackTrace''';
  }
}
