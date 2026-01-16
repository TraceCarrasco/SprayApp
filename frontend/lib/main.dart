import 'package:flutter/material.dart';
import 'package:namer_app/auth_gate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    anonKey:
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvaWxkb2dncGJ1Yml2dWlncW1qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM3MTUzNTgsImV4cCI6MjA2OTI5MTM1OH0.f2n8gquVdGel81MyE4dD9M68B-IHk-DIxyWaaunbuIc",
    url: "https://foildoggpbubivuigqmj.supabase.co",
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SprayWall',
      home: const AuthGate(),

      // Light theme
      theme: ThemeData(
        brightness: Brightness.light,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Colors.deepOrange,
          unselectedItemColor: Colors.grey,
        ),
        textTheme: GoogleFonts.playTextTheme(),
      ),

      // Dark theme
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Colors.deepOrange,
          unselectedItemColor: Colors.grey,
        ),
        textTheme: GoogleFonts.playTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),

      // 👇 this is the magic line
      themeMode: ThemeMode.dark,
    );
  }
}
