import 'dart:io';

void main() async {
  final file = File('test/simple_test.dart');
  String content = await file.readAsString();

  // Fix 1: Remove type arguments after constructor name for nonReactive
  content = content.replaceAll(
    RegExp(r'ComputedFuture\.nonReactive<([^>]+)>\('),
    r'ComputedFuture<$1>.nonReactive(',
  );

  // Fix 2: Convert single signals to lists and fix callback signatures
  // Pattern: ComputedFuture(signal, (state, input) async { ... })
  // Replace with: ComputedFuture([signal], (state) async { ... })

  // This is complex, so let's do it step by step
  // First, let's find all the patterns
  final regex = RegExp(
    r'ComputedFuture\(([^,\[\]]+),\s*\(state,\s*\w+\)\s*async\s*\{',
    multiLine: true,
  );

  content = content.replaceAllMapped(regex, (match) {
    final signal = match.group(1)!;
    return 'ComputedFuture([$signal], (state) async {';
  });

  await file.writeAsString(content);
  print('Fixed ComputedFuture constructor calls');
}
