import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const RadiantNovelApp());
}

class RadiantNovelApp extends StatelessWidget {
  const RadiantNovelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radiant Novel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Phối màu Warm Dark Theme (Đen than & Đỏ trầm)
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF161313), // Nền chính
          primary: Color(0xFF8B3A3A), // Đỏ sẫm điểm nhấn
          secondary: Color(0xFF3D1E1E), // Đỏ gạch cho nút
          onSurface: Color(0xFFEAEAEA), // Chữ màu sáng dịu
        ),
        scaffoldBackgroundColor: const Color(0xFF161313),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161313),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF282121),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), // Bo góc mượt
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
