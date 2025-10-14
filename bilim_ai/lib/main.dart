// lib/main.dart
import 'package:flutter/material.dart';
import 'splash_screen.dart'; // Импортируем наш сплэш-экран

void main() {
  runApp(const BilimAIApp());
}

class BilimAIApp extends StatelessWidget {
  const BilimAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bilim AI',
      debugShowCheckedModeBanner: false, // Убираем отладочную ленту
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B6CB0)),
        useMaterial3: true,
        fontFamily: 'Inter', // Можете добавить свой шрифт
      ),
      home: const SplashScreen(), // Начинаем с SplashScreen
    );
  }
}