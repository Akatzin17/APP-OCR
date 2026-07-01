import 'package:flutter/material.dart';
import 'package:ocr_app/main_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR App',
      home: const MainScreen(),
    );
  }
}