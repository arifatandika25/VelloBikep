import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'pengaturan_screen.dart';
import 'penyewa_screen.dart';
import 'sepeda_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.user});

  final AuthUser user;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages = [
    HomeScreen(user: widget.user),
    const SepedaScreen(),
    const PenyewaScreen(),
    PengaturanScreen(user: widget.user),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF2F9C89),
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Beranda'),
          BottomNavigationBarItem(
            icon: Icon(Icons.pedal_bike),
            label: 'Sepeda',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Penyewa'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
