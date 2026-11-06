import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';

void main() {
  runApp(const VeloBikeApp());
}

class VeloBikeApp extends StatelessWidget {
  const VeloBikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeloBike Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2F9C89),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F9C89)),
        fontFamily: 'Roboto',
      ),

      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
