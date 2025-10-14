// lib/splash_screen.dart
import 'package:flutter/material.dart';
import 'home_screen.dart'; // Мы создадим этот экран на следующем шаге

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Ждем 3 секунды, а затем переходим на главный экран
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Сюда можно добавить логотип в виде картинки
            const Text(
              'Bilim AI',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2B6CB0), // Ваш синий цвет
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Білім алудың ақылды жолы',
              style: TextStyle(
                fontSize: 18,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}