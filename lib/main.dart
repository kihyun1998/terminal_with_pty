import 'package:flutter/material.dart';
import 'package:terminal_with_pty/screens/hoem_screen.dart';

void main() {
  runApp(const TerminalManagerApp());
}

class TerminalManagerApp extends StatelessWidget {
  const TerminalManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terminal Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'SF Pro Text',
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
