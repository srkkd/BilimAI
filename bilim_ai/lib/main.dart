// lib/main.dart
import 'package:flutter/cupertino.dart';
import 'splash_screen.dart'; // Импортируем наш сплэш-экран
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ousovrpwqpcshhdwshqa.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91c292cnB3cXBjc2hoZHdzaHFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5MTQ4NDAsImV4cCI6MjA3NjQ5MDg0MH0.xID0ZmMdhaoAF0hL2KDcIuOP3xR35gvcCjYMTDZzcEA',
  );
  runApp(const BilimAIApp());
}

class BilimAIApp extends StatelessWidget {
  const BilimAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Bilim AI',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: Color(0xFF2B6CB0),
        scaffoldBackgroundColor: CupertinoColors.white,
        barBackgroundColor: CupertinoColors.systemGrey6,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(fontFamily: 'SF Pro Text', fontSize: 16),
          navLargeTitleTextStyle: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}