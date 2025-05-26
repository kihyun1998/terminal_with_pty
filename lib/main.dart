import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const TerminalLauncherApp());
}

class TerminalLauncherApp extends StatelessWidget {
  const TerminalLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terminal Launcher',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
