void main(List<String> args) async {
  Future<int> future() async {
    await Future.delayed(Duration(seconds: 1));
    return 1;
  }

  final f = future();
  f.then((value) => value * 2);
  print(await f);
}
