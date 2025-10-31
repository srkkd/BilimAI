// lib/splash_screen.dart
import 'package:flutter/cupertino.dart';
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
          CupertinoPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Bilim AI',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: Color(0xFF2B6CB0),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Білім алудың ақылды жолы',
              style: TextStyle(
                fontSize: 16,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}