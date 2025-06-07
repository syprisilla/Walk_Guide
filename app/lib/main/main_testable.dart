import 'package:flutter/material.dart';

Future<void> testableMain({bool isTest = false}) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isTest) {
    debugPrint("✅ testableMain 실행됨"); // 👈 이거 꼭 넣자
    runApp(const MyApp());
    return;
  }
  runApp(const MyApp()); // fallback
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Test Mode')),
      ),
    );
  }
}
